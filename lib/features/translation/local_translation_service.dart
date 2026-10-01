import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:bergamot_translator/bergamot_translator.dart' as bergamot;
import '../../core/storage/translation_file.dart';
import '../../core/database/library_database.dart';

const _hfApiBase = 'https://hf-mirror.com/api/models/mukowaty/firefox-translations';
const _hfModelBase = 'https://hf-mirror.com/mukowaty/firefox-translations/resolve/main';

/// 异步汇总写入辅助：收集结果，达到阈值时后台写盘，不阻塞翻译循环
/// 触发条件（任一满足就 flush）：
///   1. 累计句数达到总句数的 1%（至少 1 句）
///   2. 累计估算字节超过 64KB
class BatchFileWriter {
  final TranslationFileManager _fm;
  final String _lang;
  final String _engineId;
  final int _priority;
  final List<({int globalIndex, String text})> _buffer = [];
  int _bytes = 0;
  int _count = 0;
  static const _maxBytes = 64 * 1024; // 64KB 字节阈值
  final int _maxCount; // 句数阈值（总句数的 1%，0 = 不启用）

  /// 顺序化写盘队列：保证 append 操作不会并发错乱
  Future<void>? _lastWrite;
  /// 是否有写盘错误
  Object? _writeError;

  BatchFileWriter(this._fm, this._lang, this._engineId, this._priority,
      {int totalCount = 0})
      : _maxCount =
            totalCount > 0 ? (totalCount / 100).ceil().clamp(1, totalCount) : 0;

  /// 添加一条翻译结果到缓冲区。若触发阈值则后台写盘，不阻塞调用方。
  void add(int globalIndex, String text) {
    _buffer.add((globalIndex: globalIndex, text: text));
    _bytes += text.length * 2 + 12;
    _count++;
    if (_bytes >= _maxBytes || (_maxCount > 0 && _count >= _maxCount)) {
      _triggerFlush();
    }
  }

  /// 当阈值触发时不 await，在后台写盘
  void _triggerFlush() {
    final batch = List<({int globalIndex, String text})>.from(_buffer);
    _buffer.clear();
    _bytes = 0;
    _count = 0;
    // 链式追加到 _lastWrite 保证写盘顺序
    _lastWrite = (_lastWrite ?? Future.value()).then((_) async {
      if (_writeError != null) return; // 已有错误，跳过后续写
      try {
        await _fm.appendTranslation(
          lang: _lang, engineId: _engineId, priority: _priority, results: batch,
        );
      } catch (e) {
        _writeError = e;
      }
    });
  }

  /// 强制清空缓冲区并等待所有后台写盘完成。翻译结束时必须调用。
  Future<void> flush() async {
    if (_buffer.isNotEmpty) {
      _triggerFlush();
    }
    await _lastWrite;
    if (_writeError != null) {
      final err = _writeError!;
      _writeError = null;
      throw err;
    }
  }
}

/// Local offline translation service using Bergamot (Mozilla NMT) engine.
class LocalTranslationService {
  final String bookId;
  final String libraryPath;
  final String bookDirPath;
  final TranslationFileManager fileManager;
  static bool _serviceInitialized = false;
  static final Set<String> _loadedModels = {};
  static List<({String dir, String file})>? _cachedFiles;
  static Map<String, List<String>>? _cachedPairFiles;
  static final Map<String, List<String>> _dirFileCache = {};

  LocalTranslationService({
    required this.bookId,
    required this.libraryPath,
  })  : bookDirPath = p.join(libraryPath, 'books', bookId),
        fileManager = TranslationFileManager(p.join(libraryPath, 'books', bookId), bookId: bookId);

  // ── API 数据获取 ──────────────────────────────────────

  static Future<List<({String dir, String file})>> _getAllFiles() async {
    if (_cachedFiles != null) return _cachedFiles!;
    final resp = await http.get(Uri.parse(_hfApiBase));
    if (resp.statusCode != 200) throw Exception('无法获取模型列表 (HTTP ${resp.statusCode})');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final siblings = json['siblings'] as List<dynamic>;
    final result = <({String dir, String file})>[];
    for (final s in siblings) {
      final rf = s['rfilename'] as String;
      final slash = rf.indexOf('/');
      if (slash <= 0) continue;
      result.add((dir: rf.substring(0, slash), file: rf.substring(slash + 1)));
    }
    _cachedFiles = result.where((e) => e.file != 'model.json').toList();
    return result;
  }

  static Future<List<String>> _getPairGzFiles(String pairDir) async {
    if (_cachedPairFiles != null && _cachedPairFiles!.containsKey(pairDir)) {
      return _cachedPairFiles![pairDir]!;
    }
    final all = await _getAllFiles();
    final files = all.where((e) => e.dir == pairDir).map((e) => e.file).toList();
    _cachedPairFiles ??= {};
    _cachedPairFiles![pairDir] = files;
    return files;
  }

  // ── 下载状态检查 ──────────────────────────────────────

  /// 跟踪正在后台下载的语言（引导页选择后后台静默下载）
  static final Set<String> _pendingDownloads = {};

  /// 标记某个语言的模型正在后台下载
  static void markDownloadPending(String langCode) {
    _pendingDownloads.add(langCode);
  }

  /// 标记某个语言的模型下载完成
  static void markDownloadComplete(String langCode) {
    _pendingDownloads.remove(langCode);
  }

  /// 检查某个语言的模型是否正在后台下载中
  static bool isDownloadPending(String langCode) {
    return _pendingDownloads.contains(langCode);
  }

  static Future<Directory> _getModelsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'bergamot_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _getLangDir(String langCode) async {
    final root = await _getModelsDir();
    final dir = Directory(p.join(root.path, langCode));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> isLanguageModelDownloaded(String languageCode) async {
    // English 是桥接语言，本身不需要模型文件
    if (languageCode == 'en') return true;
    final langDir = await _getLangDir(languageCode);
    if (!await langDir.exists()) return false;
    final entries = await langDir.list().toList();
    return entries.any((e) => e.path.endsWith('.bin')) &&
           entries.any((e) => e.path.endsWith('.spm'));
  }

  static Future<bool> needsDownload(String languageCode) async {
    return !await isLanguageModelDownloaded(languageCode);
  }

  // ── 模型下载 ──────────────────────────────────────────

  static Future<void> downloadLanguageModel(
    String languageCode, {
    void Function()? onComplete,
    void Function(String error)? onError,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    try {
      final langDir = await _getLangDir(languageCode);
      final allFiles = [
        ...(await _getPairGzFiles('en-$languageCode')).map((f) => (dir: 'en-$languageCode', file: f)),
        ...(await _getPairGzFiles('$languageCode-en')).map((f) => (dir: '$languageCode-en', file: f)),
      ];
      if (allFiles.isEmpty) { onError?.call('语言 $languageCode 暂无可用模型'); return; }

      final seen = <String>{};
      final unique = <({String dir, String file})>[];
      for (final f in allFiles) { if (seen.add(f.file)) unique.add(f); }

      int done = 0;
      final total = unique.length;
      for (final task in unique) {
        final localName = task.file.endsWith('.gz') ? task.file.substring(0, task.file.length - 3) : task.file;
        final localPath = p.join(langDir.path, localName);
        if (await File(localPath).exists()) { done++; onProgress?.call(done, total); continue; }

        final resp = await http.get(Uri.parse('$_hfModelBase/${task.dir}/${task.file}'));
        if (resp.statusCode != 200) throw Exception('下载失败 HTTP ${resp.statusCode}');
        final bytes = task.file.endsWith('.gz') ? GZipDecoder().decodeBytes(resp.bodyBytes) : resp.bodyBytes;
        await File(localPath).writeAsBytes(bytes);
        done++;
        onProgress?.call(done, total);
      }
      _dirFileCache.remove(languageCode);
      onComplete?.call();
    } catch (e) { onError?.call('下载错误: $e'); }
  }

  // ── Bergamot 引擎初始化 ───────────────────────────────

  static Future<void> ensureInitialized() async {
    if (_serviceInitialized) return;
    await bergamot.BergamotTranslator.initializeServiceAsync();
    _serviceInitialized = true;
  }

  // ── 模型加载（动态检测文件，带缓存） ─────────────────

  static Future<void> _cacheDirFiles(String langDir) async {
    if (_dirFileCache.containsKey(langDir)) return;
    final dir = Directory(langDir);
    if (!await dir.exists()) return;
    _dirFileCache[langDir] = (await dir.list().toList())
        .whereType<File>().map((f) => p.basename(f.path)).toList();
  }

  static Future<void> _loadModel(String fromCode, String toCode) async {
    final key = '$fromCode$toCode';
    if (_loadedModels.contains(key)) return;
    final targetLang = (fromCode == 'en') ? toCode : fromCode;
    final langDir = await _getLangDir(targetLang);
    await _cacheDirFiles(langDir.path);
    final files = _dirFileCache[langDir.path] ?? [];
    if (files.isEmpty) throw Exception('请先下载 $targetLang 语言包');

    // ⚠️ 模型是方向性的：model.{from}{to}.bin 只能用于 from→to 翻译。
    // 旧逻辑同时接受反向文件名，导致 zh→en 会按字母序先命中
    // model.enzh.bin（反向模型），再配上 zhen 词表 → 输出中英混杂乱码。
    // 现在严格只匹配当前方向。
    final modelPrefix = '$fromCode$toCode';
    String? modelFile;
    for (final f in files) {
      if (f.startsWith('model.') && f.endsWith('.bin') && !f.startsWith('model.lex')) {
        final prefix = f.substring(6, f.length - 4).split('.').first;
        if (prefix == modelPrefix) { modelFile = f; break; }
      }
    }
    if (modelFile == null) {
      throw Exception('未找到 $fromCode→$toCode 方向的模型文件 ($modelPrefix)，请重新下载语言包');
    }

    // 只选择属于当前模型方向的 vocab 文件
    // vocab 文件命名规则:
    //   - 共享:  vocab.{prefix}.spm（常为小语种，config 中写两次）
    //   - 分离:  srcvocab.{prefix}.spm + trgvocab.{prefix}.spm（zh/ja/ko 等）
    // Bergamot 始终需要 2 个词表条目：共享时同一文件写两次，分离时两个不同的。
    final matchingVocabs = files
        .where((f) => f.endsWith('.spm') && f.contains(modelPrefix))
        .toList()
      ..sort();
    if (matchingVocabs.isEmpty) {
      throw Exception('未找到 $modelPrefix 方向的词汇表文件');
    }
    // 分离词表 → 直接取 srcvocab + trgvocab；共享词表 → 同一个写两次
    final List<String> vocabs;
    if (matchingVocabs.length >= 2) {
      // 分离词表：取 srcvocab 和 trgvocab（分别以 srcvocab/trgvocab 开头）
      final src = matchingVocabs.where((f) => f.startsWith('srcvocab')).firstOrNull;
      final tgt = matchingVocabs.where((f) => f.startsWith('trgvocab')).firstOrNull;
      if (src != null && tgt != null) {
        vocabs = [src, tgt];
      } else {
        // 可能有 vocab.{prefix}.spm 存在多个（极少见），只取前两个
        vocabs = matchingVocabs.take(2).toList();
      }
    } else {
      // 共享词表：同一文件写两次
      vocabs = [matchingVocabs.first, matchingVocabs.first];
    }

    final cfg = StringBuffer()
      ..writeln('models:\n  - ${langDir.path}/$modelFile')
      ..writeln('vocabs:')
      ..writeAll(vocabs.map((v) => '  - ${langDir.path}/$v\n'))
      ..writeln('beam-size: 1\nnormalize: 1.0\nword-penalty: 0')
      ..writeln('max-length-break: 256\nmini-batch-words: 1024')
      ..writeln('max-length-factor: 2.0\nskip-cost: true\ncpu-threads: 2')
      ..writeln('quiet: true\nquiet-translation: true')
      // A/B 实验：恢复 alignment: soft，验证是否为变慢根源（预期无关）
      ..writeln('gemm-precision: int8shiftAlphaAll\nalignment: soft');

    await bergamot.BergamotTranslator.loadModelAsync(cfg.toString(), key);
    _loadedModels.add(key);
  }

  /// 预加载一个语言的双向模型（en↔X）
  static Future<void> preloadLanguage(String lang) async {
    if (lang == 'en') return;
    await ensureInitialized();
    await _loadModel('en', lang);
    await _loadModel(lang, 'en');
  }

  // ── 翻译业务（纯翻译，不写文件 — 由调用方通过 BatchFileWriter 写入） ──

  /// 包装一个进度值，翻译方法内部持续修改，外部定时读取
  final ValueNotifier<double> progress = ValueNotifier(0.0);
  /// 全局取消表：bookId → 是否已取消
  static final Set<String> _cancelledBooks = {};

  /// 标记某个书籍的翻译为取消状态
  static void cancelBook(String bookId) => _cancelledBooks.add(bookId);
  /// 清除某个书籍的取消状态
  static void clearCancel(String bookId) => _cancelledBooks.remove(bookId);
  /// 检查某个书籍是否被标记取消
  static bool isBookCancelled(String bookId) => _cancelledBooks.contains(bookId);

  /// 直接翻译 A→B，返回 {globalIndex → 译文}
  /// 每批翻译完成后立即写入 [writer]（如果提供），实现阈值的中间落盘
  /// [overwriteExisting] 为 true 时重译所有句子（不跳过已有译文）
  Future<Map<int, String>> translateParagraph({
    required List<({int globalIndex, String text})> sentences,
    required String sourceLanguage,
    required String targetLanguage,
    bool overwriteExisting = false,
    BatchFileWriter? writer,
  }) async {
    await ensureInitialized();
    progress.value = 0.0;
    final existing = await fileManager.loadTranslation(targetLanguage);
    final result = <int, String>{};
    result.addAll(existing);

    var toTranslate = sentences.where((s) =>
        (overwriteExisting || !existing.containsKey(s.globalIndex)) && s.text.trim().isNotEmpty).toList();
    if (toTranslate.isEmpty) { progress.value = 1.0; return result; }

    // 重复句去重：章节标题/常用短语大量重复，同文本只送引擎一次
    final translationCache = <String, String>{}; // 原文 → 译文
    final uniqueTexts = <String>[];
    final seen = <String>{};
    int dupCount = 0;
    for (final s in toTranslate) {
      if (seen.add(s.text)) {
        uniqueTexts.add(s.text);
      } else {
        dupCount++;
      }
    }

    final total = toTranslate.length;
    if (dupCount > 0) {
      debugPrint('[翻译] 去重: $total 句中重复 $dupCount 句，实际送引擎 ${uniqueTexts.length} 句');
    }

    await _loadModel(sourceLanguage, targetLanguage);
    final modelKey = '$sourceLanguage$targetLanguage';

    bool cancelled = false;
    int done = 0;
    int charsDone = 0;
    int lastBatchElapsed = 0;
    const chunkSize = 16;
    final stopwatch = Stopwatch()..start();
    while (done < uniqueTexts.length) {
      if (_cancelledBooks.contains(bookId)) {
        cancelled = true;
        break;
      }

      final end = (done + chunkSize).clamp(0, uniqueTexts.length);
      final chunk = uniqueTexts.sublist(done, end);
      final chunkChars = chunk.fold<int>(0, (sum, s) => sum + s.length);
      try {
        final outputs = await bergamot.BergamotTranslator.translateMultipleAsync(
          chunk, modelKey);
        if (_cancelledBooks.contains(bookId)) {
          cancelled = true;
          break;
        }
        for (int k = 0; k < chunk.length && k < outputs.length; k++) {
          translationCache[chunk[k]] = outputs[k];
        }
      } catch (e) { debugPrint('[翻译] batch failed: $e'); }
      done = end;
      charsDone += chunkChars;
      progress.value = done / uniqueTexts.length;
      final elapsed = stopwatch.elapsedMilliseconds;
      final speed = done > 0 ? (done * 1000 / elapsed).toStringAsFixed(1) : '?';
      final cSpeed = charsDone > 0 ? (charsDone * 1000 / elapsed).toStringAsFixed(0) : '?';
      final batchMs = elapsed - lastBatchElapsed;
      lastBatchElapsed = elapsed;
      debugPrint('[翻译] $sourceLanguage→$targetLanguage: $done/${uniqueTexts.length} 句($charsDone字) | 本批$batchMs ms | 累计$speed 句/$cSpeed 字每秒');
    }
    // 回填：所有句子（含重复）从缓存取译文并写入
    // 注意：覆盖模式下必须无条件覆盖 result 中的旧译文，否则修复乱码的目的失效
    // 取消时也要回填已完成的译文，不丢进度
    for (final t in toTranslate) {
      final cached = translationCache[t.text];
      if (cached != null) {
        result[t.globalIndex] = cached;
        writer?.add(t.globalIndex, cached);
      }
    }
    await writer?.flush();
    progress.value = 1.0;
    if (!cancelled) {
      final totalMs = stopwatch.elapsedMilliseconds;
      final avgSpeed = (total * 1000 / totalMs).toStringAsFixed(1);
      debugPrint('[翻译] $sourceLanguage→$targetLanguage: 完成 $total 句 | ${totalMs}ms | $avgSpeed 句/秒');
    } else {
      debugPrint('[翻译] $sourceLanguage→$targetLanguage: 已取消，已保存 ${result.length - existing.length} 句新译文');
    }
    return result;
  }

  /// 英语中转翻译，返回 {globalIndex → 译文}
  /// 每批翻译完成后立即写入 [writer]（如果提供），实现阈值的中间落盘
  /// [overwriteExisting] 同 translateParagraph
  Future<Map<int, String>> translateWithRelay({
    required List<({int globalIndex, String text})> sentences,
    required String sourceLanguage,
    required String targetLanguage,
    bool overwriteExisting = false,
    BatchFileWriter? writer,
  }) async {
    await ensureInitialized();
    progress.value = 0.0;
    final existing = await fileManager.loadTranslation(targetLanguage);
    final result = <int, String>{};
    result.addAll(existing);

    var toTranslate = sentences.where((s) =>
        (overwriteExisting || !existing.containsKey(s.globalIndex)) && s.text.trim().isNotEmpty).toList();
    if (toTranslate.isEmpty) { progress.value = 1.0; return result; }

    // 重复句去重：同文本只送引擎一次
    final translationCache = <String, String>{};
    final uniqueTexts = <String>[];
    final seen = <String>{};
    int dupCount = 0;
    for (final s in toTranslate) {
      if (seen.add(s.text)) {
        uniqueTexts.add(s.text);
      } else {
        dupCount++;
      }
    }

    final total = toTranslate.length;
    if (dupCount > 0) {
      debugPrint('[翻译] relay 去重: $total 句中重复 $dupCount 句，实际送引擎 ${uniqueTexts.length} 句');
    }

    await _loadModel(sourceLanguage, 'en');
    await _loadModel('en', targetLanguage);
    final aKey = '${sourceLanguage}en', bKey = 'en$targetLanguage';

    bool cancelled = false;
    int done = 0;
    int charsDone = 0;
    int lastBatchElapsed = 0;
    const chunkSize = 16;
    final stopwatch = Stopwatch()..start();
    while (done < uniqueTexts.length) {
      if (_cancelledBooks.contains(bookId)) {
        cancelled = true;
        break;
      }

      final end = (done + chunkSize).clamp(0, uniqueTexts.length);
      final chunk = uniqueTexts.sublist(done, end);
      final chunkChars = chunk.fold<int>(0, (sum, s) => sum + s.length);
      try {
        final finalOut = await bergamot.BergamotTranslator.pivotMultipleAsync(
          chunk, aKey, bKey);
        if (_cancelledBooks.contains(bookId)) {
          cancelled = true;
          break;
        }
        for (int k = 0; k < chunk.length && k < finalOut.length; k++) {
          translationCache[chunk[k]] = finalOut[k];
        }
      } catch (e) { debugPrint('[翻译] relay batch failed: $e'); }
      done = end;
      charsDone += chunkChars;
      progress.value = done / uniqueTexts.length;
      final elapsed = stopwatch.elapsedMilliseconds;
      final speed = done > 0 ? (done * 1000 / elapsed).toStringAsFixed(1) : '?';
      final cSpeed = charsDone > 0 ? (charsDone * 1000 / elapsed).toStringAsFixed(0) : '?';
      final batchMs = elapsed - lastBatchElapsed;
      lastBatchElapsed = elapsed;
      debugPrint('[翻译] relay $sourceLanguage→en→$targetLanguage: $done/${uniqueTexts.length} 句($charsDone字) | 本批$batchMs ms | 累计$speed 句/$cSpeed 字每秒');
    }
    // 回填：取消时也要写入已完成的译文
    for (final t in toTranslate) {
      final cached = translationCache[t.text];
      if (cached != null) {
        result[t.globalIndex] = cached;
        writer?.add(t.globalIndex, cached);
      }
    }
    await writer?.flush();
    progress.value = 1.0;
    if (!cancelled) {
      final totalMs = stopwatch.elapsedMilliseconds;
      final avgSpeed = (total * 1000 / totalMs).toStringAsFixed(1);
      debugPrint('[翻译] relay $sourceLanguage→en→$targetLanguage: 完成 $total 句 | ${totalMs}ms | $avgSpeed 句/秒');
    } else {
      debugPrint('[翻译] relay $sourceLanguage→en→$targetLanguage: 已取消，已保存 ${result.length - existing.length} 句新译文');
    }
    return result;
  }

  Future<void> clearTranslation(String langCode) async {
    await fileManager.deleteTranslation(langCode);
    final db = LibraryDatabase();
    final current = await db.getSetting('translated_languages');
    final langs = (current ?? '').split(',').where((l) => l.isNotEmpty && l != langCode).toList();
    await db.setSetting('translated_languages', langs.join(','));
  }
}