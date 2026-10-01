import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'content_dat_reader.dart';

/// content_{lang}.dat 二进制协议定义
///
/// ## 文件结构
/// ┌────────────────────────────────────────────────────┐
/// │ Header (16 bytes, 定长)                           │
/// │   Magic (4B): "TRLX"                             │
/// │   Version (2B, uint16)                           │
/// │   Chapter Count (2B, uint16)                     │
/// │   Chapter Index Offset (4B, uint32)              │
/// │   Chapter Index Length (4B, uint32)              │
/// ├────────────────────────────────────────────────────┤
/// │ Translation Data (变长, 按章节)                    │
/// │   Chapter 0: engineId + priority + texts         │
/// │   Chapter 1: ...                                 │
/// ├────────────────────────────────────────────────────┤
/// │ Chapter Index (变长)                              │
/// │   Entry 0: contentOffset(V) | contentLength(V)   │
/// │   Entry 1: ...                                   │
/// └────────────────────────────────────────────────────┘
///
/// 翻译文本按句顺序排列（不存 globalIndex，通过章节句号范围推算）。
/// 每次追加都全量重写文件（数据区 + Index + Header 回填），天然无碎片。
const _translationMagic = 'TRLX';
const _translationVersion = 1;
const _translationHeaderSize = 16;

// ═══════════════ Varint 编解码 ═══════════════

/// 从 [data] 的 [offset] 读取一个 varint，返回 (值, 新偏移)
(int, int) _readVarint(Uint8List data, int offset) {
  int result = 0, shift = 0;
  while (true) {
    final byte = data[offset++];
    result |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) break;
    shift += 7;
  }
  return (result, offset);
}

/// 读取一个 UTF-8 字符串（前有 varint 长度），返回 (字符串, 新偏移)
(String, int) _readString(Uint8List data, int offset) {
  final (len, off) = _readVarint(data, offset);
  if (len > data.length - off) return ('', off);
  return (utf8.decode(data.sublist(off, off + len)), off + len);
}

/// 将 [value] 的 varint 编码追加到 [buffer]
void _writeVarint(BytesBuilder buffer, int value) {
  var v = value;
  while (v >= 0x80) {
    buffer.add([(v & 0x7F) | 0x80]);
    v >>= 7;
  }
  buffer.add([v & 0x7F]);
}

// ═══════════════ 数据模型 ═══════════════

/// 某章节解析后的翻译数据
class ChapterTranslationData {
  final String engineId;
  final int priority;
  final List<String> texts;

  const ChapterTranslationData({
    required this.engineId,
    required this.priority,
    required this.texts,
  });

  int get sentenceCount => texts.length;

  /// 映射为 {globalIndex → text}；空串（占位未翻译）不进入映射
  Map<int, String> toGlobalIndexMap(int baseGlobalIndex) {
    final map = <int, String>{};
    for (int i = 0; i < texts.length; i++) {
      if (texts[i].isNotEmpty) map[baseGlobalIndex + i] = texts[i];
    }
    return map;
  }
}

// ═══════════════ 读取器 ═══════════════

/// 翻译文件读取器
///
/// 构造时只解析 Header + Chapter Index，正文按需按章读取。
/// 任何字节损坏（垃圾条目/越界/非法 UTF-8）都降级为"该章无翻译"，不抛异常。
class TranslationFileReader {
  final Uint8List _data;
  final List<({int offset, int length})> _chapterIndex = [];

  TranslationFileReader(this._data) {
    if (_data.length < _translationHeaderSize) return;

    final magic = utf8.decode(_data.sublist(0, 4), allowMalformed: true);
    if (magic != _translationMagic) return;

    final dv = ByteData.sublistView(_data);
    final chapterCount = dv.getUint16(6, Endian.little);
    final indexOffset = dv.getUint32(8, Endian.little);
    if (indexOffset < _translationHeaderSize || indexOffset >= _data.length) return;

    int p = indexOffset;
    for (int i = 0; i < chapterCount && p < _data.length; i++) {
      final (co, o1) = _readVarint(_data, p);
      if (o1 >= _data.length) break;
      final (cl, o2) = _readVarint(_data, o1);
      _chapterIndex.add((offset: co, length: cl));
      p = o2; // 必须推进到第二个 varint 之后，否则从第二条起全部错位
    }
  }

  int get chapterCount => _chapterIndex.length;
  bool get hasData => _chapterIndex.isNotEmpty;

  /// 读取指定章节，索引项无效或数据损坏时返回 null
  ChapterTranslationData? readChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapterIndex.length) return null;

    final entry = _chapterIndex[chapterIndex];
    if (entry.offset < _translationHeaderSize || entry.length <= 0 ||
        entry.offset + entry.length > _data.length) {
      return null;
    }

    try {
      int p = entry.offset;
      final end = entry.offset + entry.length;

      final (engineId, o1) = _readString(_data, p);
      if (engineId.isEmpty || o1 > end) return null;
      final (priority, o2) = _readVarint(_data, o1);
      if (o2 > end) return null;
      final (count, o3) = _readVarint(_data, o2);
      if (o3 > end) return null;

      final texts = <String>[];
      p = o3;
      for (int i = 0; i < count && p < end; i++) {
        final (text, o4) = _readString(_data, p);
        if (o4 > end) return null;
        p = o4;
        texts.add(text);
      }
      return ChapterTranslationData(
        engineId: engineId, priority: priority, texts: texts,
      );
    } catch (_) {
      return null; // FormatException / RangeError → 视为该章无翻译
    }
  }

  /// 全部读出为 {globalIndex → text}。
  /// [perChapterSentenceCounts] 为 content.dat 每章真实句数，用于
  /// 推进 globalIndex 基准（比文件内记录更可信）。
  Map<int, String> readAll(List<int> perChapterSentenceCounts) {
    final map = <int, String>{};
    int baseGI = 0;
    for (int i = 0; i < _chapterIndex.length; i++) {
      final expected =
          i < perChapterSentenceCounts.length ? perChapterSentenceCounts[i] : null;
      final ch = readChapter(i);
      if (ch != null) map.addAll(ch.toGlobalIndexMap(baseGI));
      baseGI += expected ?? ch?.sentenceCount ?? 0;
    }
    return map;
  }
}

// ═══════════════ 写入器 ═══════════════

/// 翻译文件写入器：Header(16B) → 数据区 → Index → Header 回填
class TranslationFileWriter {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  void _writeUint16(int v) => _buffer.add([v & 0xFF, (v >> 8) & 0xFF]);
  void _writeUint32(int v) =>
      _buffer.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  /// 写入 Header（offset/length 先占位，之后 backfill）
  void writeHeader(int chapterCount) {
    _buffer.add(utf8.encode(_translationMagic));
    _writeUint16(_translationVersion);
    _writeUint16(chapterCount);
    _writeUint32(0); // index offset 占位
    _writeUint32(0); // index length 占位
  }

  /// 写入一章翻译数据块，返回 (offset, length) 供 Index 使用
  ({int offset, int length}) writeChapter({
    required String engineId,
    required int priority,
    required List<String> texts,
  }) {
    final start = _buffer.length;

    final eb = utf8.encode(engineId);
    _writeVarint(_buffer, eb.length);
    _buffer.add(eb);
    _writeVarint(_buffer, priority);
    _writeVarint(_buffer, texts.length);
    for (final t in texts) {
      final tb = utf8.encode(t);
      _writeVarint(_buffer, tb.length);
      _buffer.add(tb);
    }
    return (offset: start, length: _buffer.length - start);
  }

  /// 完成：写入 Index、回填 Header，返回文件字节
  Uint8List finish(List<({int offset, int length})> entries) {
    final indexStart = _buffer.length;
    for (final e in entries) {
      _writeVarint(_buffer, e.offset);
      _writeVarint(_buffer, e.length);
    }
    final indexLength = _buffer.length - indexStart;
    final bytes = _buffer.takeBytes();
    // takeBytes 返回的是独立数组，直接原地回填 Header
    void patch(int pos, int v) {
      for (int i = 0; i < 4; i++) {
        bytes[pos + i] = (v >> (8 * i)) & 0xFF;
      }
    }
    patch(8, indexStart);
    patch(12, indexLength);
    return bytes;
  }
}

// ═══════════════ 管理器 ═══════════════

/// 翻译文件管理器
class TranslationFileManager {
  static const String _prefix = 'content_';
  static const String _suffix = '.dat';

  final String _bookDirPath;
  final String _bookId;

  TranslationFileManager(this._bookDirPath, {String? bookId})
      : _bookId = bookId ?? '';

  String _path(String lang) => p.join(_bookDirPath, '$_prefix$lang$_suffix');

  /// 获取 content.dat 中每章的句数
  Future<List<int>> _getPerChapterSentenceCounts() async {
    try {
      if (_bookId.isEmpty) return [];
      final datFile = File(p.join(_bookDirPath, 'content.dat'));
      if (!await datFile.exists()) return [];
      final reader = ContentDatReader(await datFile.readAsBytes());
      return [
        for (int i = 0; i < reader.chapterCount; i++)
          reader.readChapter(i)?.sentenceCount ?? 0,
      ];
    } catch (_) {
      return [];
    }
  }

  // ── 读取 ──

  /// 读取全部翻译为 {globalIndex → text}
  Future<Map<int, String>> loadTranslation(String lang,
      {List<int>? perChapterSentenceCounts}) async {
    final file = File(_path(lang));
    if (!await file.exists()) return {};
    final counts = perChapterSentenceCounts ?? await _getPerChapterSentenceCounts();
    return TranslationFileReader(await file.readAsBytes()).readAll(counts);
  }

  // ── 写入 ──

  /// 追加一章翻译；与该章已有译文按句位合并，覆盖不丢句。
  Future<void> appendChapterTranslation({
    required String lang,
    required String engineId,
    required int priority,
    required int chapterIndex,
    required List<String> texts,
    required int totalChapterCount,
  }) async {
    if (texts.isEmpty) return;
    final file = File(_path(lang));

    // 1. 读旧文件，解析 Index
    final oldBytes = await file.exists() ? await file.readAsBytes() : null;
    final oldReader =
        oldBytes != null ? TranslationFileReader(oldBytes) : null;
    final index = List<({int offset, int length})>.of(oldReader?._chapterIndex ?? const []);
    while (index.length < totalChapterCount) {
      index.add((offset: 0, length: 0));
    }

    // 2. 同章合并：保留已存译文，新译文按句位覆盖
    List<String> merged = texts;
    final oldCh = oldReader?.readChapter(chapterIndex);
    if (oldCh != null && oldCh.texts.isNotEmpty) {
      merged = List<String>.of(oldCh.texts);
      if (merged.length < texts.length) merged.addAll(List.filled(texts.length - merged.length, ''));
      for (int i = 0; i < texts.length; i++) {
        if (texts[i].isNotEmpty) merged[i] = texts[i];
      }
      while (merged.isNotEmpty && merged.last.isEmpty) {
        merged.removeLast(); // 修剪尾部占位空串
      }
    }
    if (merged.isEmpty) return;

    // 3. 全量重写：Header + 旧数据区 + 新章块 + Index + 回填
    final fw = TranslationFileWriter()..writeHeader(totalChapterCount);
    if (oldBytes != null && oldBytes.length > _translationHeaderSize) {
      fw._buffer.add(oldBytes.sublist(_translationHeaderSize));
    }
    index[chapterIndex] = fw.writeChapter(
      engineId: engineId, priority: priority, texts: merged,
    );
    await file.writeAsBytes(fw.finish(index));
  }

  /// 追加一批翻译（按 globalIndex 分章写入）
  Future<void> appendTranslation({
    required String lang,
    required String engineId,
    required int priority,
    required List<({int globalIndex, String text})> results,
  }) async {
    if (results.isEmpty) return;

    final perChapterCounts = await _getPerChapterSentenceCounts();
    if (perChapterCounts.isEmpty) {
      await appendChapterTranslation(
        lang: lang, engineId: engineId, priority: priority,
        chapterIndex: 0,
        texts: results.map((r) => r.text).toList(),
        totalChapterCount: 1,
      );
      return;
    }

    // 每章 globalIndex 起始边界
    final chBoundaries = <int>[0];
    for (final c in perChapterCounts) {
      chBoundaries.add(chBoundaries.last + c);
    }

    // 按章节分组，组内按句位填空占位
    final chapterGroups = <int, List<String>>{};
    for (final r in results) {
      // 最后一个 ≤ gi 的边界即所在章号
      final chIdx = chBoundaries.lastIndexWhere((b) => b <= r.globalIndex);
      if (chIdx < 0 || chIdx >= perChapterCounts.length) continue;
      final list = chapterGroups.putIfAbsent(chIdx, () => []);
      final posInCh = r.globalIndex - chBoundaries[chIdx];
      while (list.length <= posInCh) {
        list.add('');
      }
      list[posInCh] = r.text;
    }

    for (final entry in chapterGroups.entries) {
      await appendChapterTranslation(
        lang: lang, engineId: engineId, priority: priority,
        chapterIndex: entry.key, texts: entry.value,
        totalChapterCount: perChapterCounts.length,
      );
    }
  }

  // ── 删除/统计 ──

  Future<void> deleteTranslation(String lang) async {
    final file = File(_path(lang));
    if (await file.exists()) await file.delete();
  }

  /// 删除指定引擎的所有翻译记录
  Future<void> deleteEngineFromLanguage(String lang, String engineId) async {
    final file = File(_path(lang));
    if (!await file.exists()) return;

    final reader = TranslationFileReader(await file.readAsBytes());
    if (!reader.hasData) return;

    // 保留其它引擎的章节
    final kept = <int, ChapterTranslationData>{};
    for (int i = 0; i < reader.chapterCount; i++) {
      final ch = reader.readChapter(i);
      if (ch != null && ch.engineId != engineId) kept[i] = ch;
    }
    if (kept.isEmpty) {
      await file.delete();
      return;
    }

    await file.writeAsBytes(_rebuild(reader.chapterCount, (fw, i) {
      final ch = kept[i];
      return ch == null
          ? (offset: 0, length: 0)
          : fw.writeChapter(engineId: ch.engineId, priority: ch.priority, texts: ch.texts);
    }));
  }

  /// 获取某语言使用的引擎列表
  Future<List<({String engineId, int count})>> listEnginesForLanguage(
      String lang) async {
    final file = File(_path(lang));
    if (!await file.exists()) return [];
    final reader = TranslationFileReader(await file.readAsBytes());
    final map = <String, int>{};
    for (int i = 0; i < reader.chapterCount; i++) {
      final ch = reader.readChapter(i);
      if (ch != null && ch.texts.isNotEmpty) {
        map[ch.engineId] = (map[ch.engineId] ?? 0) + 1;
      }
    }
    return [for (final e in map.entries) (engineId: e.key, count: e.value)];
  }

  /// 获取总翻译句数（非空译文）
  Future<int> translationSentenceCount(String lang) async {
    final file = File(_path(lang));
    if (!await file.exists()) return 0;
    final reader = TranslationFileReader(await file.readAsBytes());
    int total = 0;
    for (int i = 0; i < reader.chapterCount; i++) {
      final ch = reader.readChapter(i);
      if (ch != null) {
        total += ch.texts.where((t) => t.isNotEmpty).length;
      }
    }
    return total;
  }

  /// 列出可用翻译语言
  Future<List<String>> listAvailableLanguages() async {
    final dir = Directory(_bookDirPath);
    if (!await dir.exists()) return [];
    final list = <String>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) continue;
      final lang = name.substring(_prefix.length, name.length - _suffix.length);
      if (lang.isNotEmpty && lang.length <= 7) list.add(lang);
    }
    return list;
  }

  /// 全量重建文件：[writeChapterAt] 决定每章写入内容（不写则占位空条目）
  static Uint8List _rebuild(
      int chapterCount,
      ({int offset, int length}) Function(TranslationFileWriter fw, int i)
          writeChapterAt) {
    final fw = TranslationFileWriter()..writeHeader(chapterCount);
    final entries = [for (int i = 0; i < chapterCount; i++) writeChapterAt(fw, i)];
    return fw.finish(entries);
  }
}
