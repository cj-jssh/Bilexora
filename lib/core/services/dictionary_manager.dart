import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

// ═══════════════════════════════════════════════════════
//  外部词典模型 (可自由添加，和翻译引擎平行)
// ═══════════════════════════════════════════════════════

/// 词典类型
enum DictSourceType { sqlite, mdx }

/// 外部词典源
class DictSource {
  final String id;
  final String name;
  final DictSourceType type;
  final String filePath;
  final String language;
  final int sortOrder;
  final String? description;
  final int entryCount;

  const DictSource({
    required this.id,
    required this.name,
    required this.type,
    required this.filePath,
    this.language = 'en',
    this.sortOrder = 0,
    this.description,
    this.entryCount = 0,
  });

  DictSource copyWith({
    String? id,
    String? name,
    DictSourceType? type,
    String? filePath,
    String? language,
    int? sortOrder,
    String? description,
    int? entryCount,
  }) {
    return DictSource(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      language: language ?? this.language,
      sortOrder: sortOrder ?? this.sortOrder,
      description: description ?? this.description,
      entryCount: entryCount ?? this.entryCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'filePath': filePath,
        'language': language,
        'description': description,
        'sortOrder': sortOrder,
        'entryCount': entryCount,
      };

  factory DictSource.fromJson(Map<String, dynamic> j) => DictSource(
        id: j['id'] as String,
        name: j['name'] as String,
        type: DictSourceType.values.byName(j['type'] as String),
        filePath: j['filePath'] as String,
        language: j['language'] as String? ?? 'en',
        description: j['description'] as String?,
        sortOrder: j['sortOrder'] as int? ?? 0,
        entryCount: j['entryCount'] as int? ?? 0,
      );
}

// ═══════════════════════════════════════════════════════
//  词典查询结果
// ═══════════════════════════════════════════════════════

/// 从单个词典源查到的结果
class DictQueryResult {
  final String word;
  final String? phonetic;
  final String? translation;   // 简明释义（纯文本）
  final String? definition;    // 详细英文释义
  final String? definitionCn;  // 详细中文释义
  final String? pos;           // 词性
  final String? detail;        // 完整 HTML/JSON 详情
  final String sourceId;       // 来自哪个词典

  const DictQueryResult({
    required this.word,
    this.phonetic,
    this.translation,
    this.definition,
    this.definitionCn,
    this.pos,
    this.detail,
    required this.sourceId,
  });
}

// ═══════════════════════════════════════════════════════
//  词典源解析器接口
// ═══════════════════════════════════════════════════════

abstract class DictSourceParser {
  String get sourceId;
  String get sourceName;

  /// 精确查词
  Future<DictQueryResult?> lookup(String word);

  /// 前缀提示
  Future<List<DictQueryResult>> suggestions(String prefix, {int limit});

  /// 是否可用
  bool get isAvailable;
}

// ═══════════════════════════════════════════════════════
//  SQLite 词典读取器（兼容 pure-dict / ECDICT 格式）
// ═══════════════════════════════════════════════════════

/// SQLite 词典数据库读取器
///
/// 表结构:
///   words 表: word, phonetic, translation, definition, definition_cn,
///             pos, tag, bnc, frq, exchange, detail, audio
///   zh_index 表: seg, word (中文 bigram 倒排索引，可选)
class SqliteDictReader implements DictSourceParser {
  final DictSource source;
  sqflite.Database? _db;
  bool _opened = false;

  SqliteDictReader(this.source);

  @override
  String get sourceId => source.id;

  @override
  String get sourceName => source.name;

  @override
  bool get isAvailable => _opened && _db != null;

  static final _cjkRe = RegExp(r'[\u4e00-\u9fff]');

  Future<void> open() async {
    if (_opened) return;
    try {
      final file = File(source.filePath);
      if (!await file.exists()) {
        debugPrint('[词典] SQLite 文件不存在: ${source.filePath}');
        return;
      }
      _db = await sqflite.openDatabase(source.filePath, readOnly: true);
      _opened = true;
      debugPrint('[词典] 已加载 SQLite 词典: ${source.name}');
    } catch (e) {
      debugPrint('[词典] 打开 SQLite 失败: ${source.name}: $e');
    }
  }

  @override
  Future<DictQueryResult?> lookup(String word) async {
    if (!isAvailable) return null;
    final query = word.trim();
    if (query.isEmpty) return null;

    try {
      var rows = await _db!.query(
        'words',
        where: 'word = ?',
        whereArgs: [query],
        limit: 1,
      );
      if (rows.isEmpty) {
        rows = await _db!.query(
          'words',
          where: 'word = ? COLLATE NOCASE',
          whereArgs: [query],
          limit: 1,
        );
      }
      if (rows.isEmpty) return null;

      final row = rows.first;
      return DictQueryResult(
        word: row['word'] as String? ?? query,
        phonetic: row['phonetic'] as String?,
        translation: row['translation'] as String?,
        definition: row['definition'] as String?,
        definitionCn: row['definition_cn'] as String?,
        pos: row['pos'] as String?,
        detail: row['detail'] as String?,
        sourceId: source.id,
      );
    } catch (e) {
      debugPrint('[词典] SQLite 查词失败: $e');
      return null;
    }
  }

  @override
  Future<List<DictQueryResult>> suggestions(String prefix, {int limit = 12}) async {
    if (!isAvailable) return [];
    final query = prefix.trim().toLowerCase();
    if (query.isEmpty) return [];

    try {
      List<Map<String, Object?>> rows;

      if (_cjkRe.hasMatch(query)) {
        rows = await _searchChinese(query, limit);
      } else {
        rows = await _db!.query(
          'words',
          columns: ['word', 'phonetic', 'translation'],
          where: 'word LIKE ? AND length(word) <= ?',
          whereArgs: ['$query%', (query.length + 12).toString()],
          orderBy: 'length(word) ASC, word ASC',
          limit: limit,
        );
      }
      return rows.map((row) => DictQueryResult(
            word: row['word'] as String? ?? '',
            phonetic: row['phonetic'] as String?,
            translation: row['translation'] as String?,
            sourceId: source.id,
          )).toList();
    } catch (e) {
      debugPrint('[词典] SQLite 建议查询失败: $e');
      return [];
    }
  }

  Future<List<Map<String, Object?>>> _searchChinese(String query, int limit) async {
    // 检查 zh_index 表是否存在
    try {
      await _db!.rawQuery('SELECT 1 FROM zh_index LIMIT 1');
    } catch (_) {
      return []; // 没有中文索引
    }

    final grams = <String>[];
    for (var i = 0; i < query.length - 1; i++) {
      grams.add(query.substring(i, i + 2));
    }
    if (query.length == 1) grams.add(query);
    if (grams.isEmpty) return [];

    final placeholders = List.filled(grams.length, '?').join(',');
    return _db!.rawQuery(
      '''
      SELECT w.word, w.phonetic, w.translation
      FROM zh_index z
      JOIN words w ON w.word = z.word
      WHERE z.seg IN ($placeholders)
      GROUP BY w.word
      ORDER BY COUNT(*) DESC
      LIMIT ?
      ''',
      [...grams, limit],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opened = false;
  }
}

// ═══════════════════════════════════════════════════════
//  MDX 词典读取器（占位 — 待实现）
// ═══════════════════════════════════════════════════════

class MdxDictReader implements DictSourceParser {
  final DictSource source;

  MdxDictReader(this.source);

  @override
  String get sourceId => source.id;

  @override
  String get sourceName => source.name;

  @override
  bool get isAvailable => false; // 尚未实现

  @override
  Future<DictQueryResult?> lookup(String word) async => null;

  @override
  Future<List<DictQueryResult>> suggestions(String prefix, {int limit = 12}) async => [];
}

// ═══════════════════════════════════════════════════════
//  词典管理器
// ═══════════════════════════════════════════════════════

class _DictLoader {
  final DictSource source;
  final DictSourceParser parser;
  _DictLoader({required this.source, required this.parser});
}

class DictionaryManager {
  static final DictionaryManager _instance = DictionaryManager._();
  factory DictionaryManager() => _instance;
  DictionaryManager._();

  final List<_DictLoader> _loaders = [];
  bool _initialized = false;

  /// 按 sortOrder 顺序初始化所有词典源（增量添加，不清除已加载的）
  Future<void> initialize(List<DictSource> sources) async {
    for (final source in sources) {
      // 如果已加载则跳过
      if (_loaders.any((l) => l.source.id == source.id)) continue;
      final parser = _createParser(source);
      if (parser == null) continue;
      await _openParser(parser);
      _loaders.add(_DictLoader(source: source, parser: parser));
    }
    if (_loaders.isNotEmpty) _initialized = true;
  }

  DictSourceParser? _createParser(DictSource source) {
    switch (source.type) {
      case DictSourceType.sqlite:
        return SqliteDictReader(source);
      case DictSourceType.mdx:
        return MdxDictReader(source);
    }
  }

  Future<void> _openParser(DictSourceParser parser) async {
    if (parser is SqliteDictReader) {
      await parser.open();
    }
    // MDX 打开逻辑待实现
  }

  Future<void> addSource(DictSource source) async {
    final parser = _createParser(source);
    if (parser == null) return;
    await _openParser(parser);
    _loaders.add(_DictLoader(source: source, parser: parser));
    _initialized = true;
  }

  Future<void> removeSource(String sourceId) async {
    final idx = _loaders.indexWhere((l) => l.source.id == sourceId);
    if (idx < 0) return;
    final loader = _loaders.removeAt(idx);
    if (loader.parser is SqliteDictReader) {
      await (loader.parser as SqliteDictReader).close();
    }
  }

  /// 按排序顺序遍历所有可用词典，返回第一个命中结果
  Future<DictQueryResult?> lookup(String word) async {
    if (!_initialized || _loaders.isEmpty) return null;
    final query = word.trim().toLowerCase();

    for (final loader in _loaders) {
      if (!loader.parser.isAvailable) continue;
      try {
        final result = await loader.parser.lookup(query);
        if (result != null) return result;
      } catch (e) {
        debugPrint('[词典] ${loader.source.name} 查词失败: $e');
      }
    }
    return null;
  }

  /// 合并多词典的前缀提示，去重，按词典顺序优先
  Future<List<DictQueryResult>> suggestions(String prefix, {int limit = 12}) async {
    if (!_initialized) return [];
    final query = prefix.trim().toLowerCase();
    if (query.isEmpty) return [];

    final seen = <String>{};
    final results = <DictQueryResult>[];

    for (final loader in _loaders) {
      if (!loader.parser.isAvailable) continue;
      try {
        final items = await loader.parser.suggestions(query, limit: limit);
        for (final item in items) {
          if (seen.add(item.word.toLowerCase()) && results.length < limit) {
            results.add(item);
          }
        }
      } catch (e) {
        debugPrint('[词典] ${loader.source.name} 建议失败: $e');
      }
      if (results.length >= limit) break;
    }
    return results;
  }
}

// ═══════════════════════════════════════════════════════
//  词典文件管理
// ═══════════════════════════════════════════════════════

class DictFileManager {
  static const _dictsDirName = 'external_dicts';

  static Future<Directory> getDictsDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDocDir.path, _dictsDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<File>> listDictFiles() async {
    final dir = await getDictsDir();
    if (!await dir.exists()) return [];
    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite') || f.path.endsWith('.mdx'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  static Future<String?> copyToDictsDir(String sourcePath) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;

      final dir = await getDictsDir();
      final dest = File(p.join(dir.path, p.basename(sourcePath)));
      if (await dest.exists()) {
        final name = p.basenameWithoutExtension(sourcePath);
        final ext = p.extension(sourcePath);
        int counter = 1;
        String newPath;
        do {
          newPath = p.join(dir.path, '${name}_$counter$ext');
          counter++;
        } while (await File(newPath).exists());
        await src.copy(newPath);
        return newPath;
      }
      await src.copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('[词典] 复制词典文件失败: $e');
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════
//  外部词典安装/管理
// ═══════════════════════════════════════════════════════

/// 从 SQLite 文件创建词典源
Future<DictSource?> createSqliteDictSource(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final db = await sqflite.openDatabase(filePath, readOnly: true);
    int entryCount = 0;
    String? name;

    try {
      final result = await db.rawQuery('SELECT COUNT(*) AS c FROM words');
      entryCount = (result.first['c'] as num?)?.toInt() ?? 0;
      name = p.basenameWithoutExtension(filePath);
    } catch (_) {}

    await db.close();

    return DictSource(
      id: 'sqlite_${DateTime.now().millisecondsSinceEpoch}',
      name: name ?? p.basenameWithoutExtension(filePath),
      type: DictSourceType.sqlite,
      filePath: filePath,
      language: 'en',
      entryCount: entryCount,
      description: 'SQLite 词典 ($entryCount 词条)',
    );
  } catch (e) {
    debugPrint('[词典] 创建 SQLite 词典源失败: $e');
    return null;
  }
}