import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../database/library_database.dart';
import '../models/models.dart';
import 'dictionary_manager.dart';

import '../state/dictionary_providers.dart';

/// 词典查询结果（UI 层使用，聚合多源）
class WordDefinition {
  final String word;
  final String? phonetic;
  final String? phoneticAudioUrl;
  final String? origin;
  final List<Meaning> meanings;
  final String? sourceName; // 来自哪个词典

  const WordDefinition({
    required this.word,
    this.phonetic,
    this.phoneticAudioUrl,
    this.origin,
    this.meanings = const [],
    this.sourceName,
  });

  String get firstDefinition =>
      meanings.isNotEmpty && meanings.first.definitions.isNotEmpty
          ? meanings.first.definitions.first.definition
          : '';

  String get partOfSpeechSummary =>
      meanings.isNotEmpty ? meanings.first.partOfSpeech : '';
}

class Meaning {
  final String partOfSpeech;
  final List<Definition> definitions;

  const Meaning({required this.partOfSpeech, this.definitions = const []});
}

class Definition {
  final String definition;
  final String? example;
  final List<String> synonyms;
  final List<String> antonyms;

  const Definition({
    required this.definition,
    this.example,
    this.synonyms = const [],
    this.antonyms = const [],
  });
}

/// 统一的查词服务
///
/// 查询顺序（按配置的词典排序）：
/// 1. 所有已配置的外部词典（SQLite / MDX / 内置格式）
/// 2. 本地 SQLite 缓存
/// 3. FreeDictionary API（仅英语兜底）
class DictionaryService {
  static const _freeDictApi = 'https://api.dictionaryapi.dev/api/v2/entries/en';

  /// 查词：按词典配置顺序查询，返回第一个非空结果
  static Future<WordDefinition?> lookup(String word, {String language = 'en'}) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // ── 1. 外部词典（用户配置的，支持拖拽排序） ──
    final external = await _lookupExternal(normalized);
    if (external != null) return external;

    // ── 2. 本地 SQLite 缓存 ──
    final db = LibraryDatabase();
    final cached = await db.getCachedDefinition(normalized, language);
    if (cached != null) {
      if (cached.definition != null || cached.phonetic != null) {
        return _fromCache(cached);
      }
      // 缓存标记了空结果（404）
      return WordDefinition(word: normalized);
    }

    // ── 3. 在线 API（仅英语） ──
    if (language == 'en') {
      final online = await _lookupOnline(normalized, db);
      if (online != null) return online;
    }

    return WordDefinition(word: normalized);
  }

  /// 从外部配置的词典查询
  static Future<WordDefinition?> _lookupExternal(String word) async {
    try {
      final manager = DictionaryManager();
      // 尝试查词，如果未初始化则尝试从持久化加载
      var result = await manager.lookup(word);
      if (result == null) {
        final sources = await DictSourcePersistence().load();
        if (sources.isNotEmpty) {
          await manager.initialize(sources);
          result = await manager.lookup(word);
        }
      }
      if (result == null) return null;

      // DictQueryResult → WordDefinition
      final meanings = <Meaning>[];

      // 1. 尝试使用 translation（简明中文释义，最常用）
      if (result.translation != null && result.translation!.trim().isNotEmpty) {
        final lines = result.translation!
            .split(RegExp(r'[；;]'))
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          final defs = lines
              .map((l) => Definition(definition: l.trim()))
              .toList();
          meanings.add(Meaning(partOfSpeech: result.pos ?? '', definitions: defs));
        }
      }

      // 2. 尝试使用 definitionCn（详细中文释义）
      if (meanings.isEmpty &&
          result.definitionCn != null &&
          result.definitionCn!.trim().isNotEmpty) {
        final defs = result.definitionCn!
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => Definition(definition: l.trim()))
            .toList();
        if (defs.isNotEmpty) {
          meanings.add(Meaning(partOfSpeech: result.pos ?? '', definitions: defs));
        }
      }

      // 3. 尝试用 definition 英文释义（无中文资料时）
      if (meanings.isEmpty &&
          result.definition != null &&
          result.definition!.trim().isNotEmpty) {
        final defs = result.definition!
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => Definition(definition: l.trim()))
            .toList();
        if (defs.isNotEmpty) {
          meanings.add(Meaning(partOfSpeech: result.pos ?? '', definitions: defs));
        }
      }

      return WordDefinition(
        word: result.word,
        phonetic: result.phonetic,
        meanings: meanings,
        sourceName: result.sourceId,
      );
    } catch (e) {
      debugPrint('[词典] 外部查询失败: $e');
      return null;
    }
  }

  /// 从 FreeDictionary API 查询
  static Future<WordDefinition?> _lookupOnline(String word, LibraryDatabase db) async {
    try {
      final url = Uri.parse('$_freeDictApi/${Uri.encodeComponent(word)}');
      final resp = await http.get(url).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as List<dynamic>;
        if (json.isNotEmpty) {
          final def = _parseApiResponse(json.first as Map<String, dynamic>);

          // 写 SQLite 缓存
          await db.cacheDefinition(DictionaryCache(
            word: word,
            language: 'en',
            phonetic: def.phonetic,
            definition: def.meanings
                .expand((m) => m.definitions)
                .map((d) => d.definition)
                .join('\n'),
            partOfSpeech: def.meanings.isNotEmpty
                ? def.meanings.first.partOfSpeech : null,
            cachedAt: DateTime.now(),
          ));
          return def;
        }
      } else if (resp.statusCode == 404) {
        await db.cacheDefinition(DictionaryCache(
          word: word, language: 'en', cachedAt: DateTime.now(),
        ));
      }
    } on http.ClientException catch (e) {
      debugPrint('[词典] 网络错误: $word, $e');
    } catch (e) {
      debugPrint('[词典] 在线查询失败: $word, $e');
    }
    return null;
  }

  /// 前缀搜索：合并多词典结果
  static Future<List<String>> suggestions(String prefix, {int limit = 12}) async {
    final query = prefix.trim().toLowerCase();
    if (query.isEmpty) return [];

    final manager = DictionaryManager();
    final results = await manager.suggestions(query, limit: limit);
    return results.map((r) => r.word).toList();
  }

  // ── 生词本 ──

  static Future<void> saveToVocabulary({
    required String word,
    required WordDefinition definition,
    String? bookId,
    String? bookTitle,
  }) async {
    final db = LibraryDatabase();
    final entry = VocabularyEntry(
      id: const Uuid().v4(),
      word: word,
      translation: definition.phonetic != null
          ? '${definition.phonetic}  ${definition.firstDefinition}'
          : definition.firstDefinition,
      definition: definition.meanings
          .expand((m) => m.definitions)
          .map((d) => d.definition)
          .take(3)
          .join('\n'),
      exampleSentence: definition.meanings
          .expand((m) => m.definitions)
          .where((d) => d.example != null)
          .map((d) => d.example!)
          .firstOrNull,
      bookId: bookId,
      bookTitle: bookTitle,
      addedAt: DateTime.now(),
    );
    await db.addVocabulary(entry);
  }

  // ── 内部工具 ──

  static WordDefinition _fromCache(DictionaryCache cache) {
    final defs = (cache.definition ?? '')
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((l) => Definition(definition: l))
        .toList();
    return WordDefinition(
      word: cache.word,
      phonetic: cache.phonetic,
      meanings: [
        Meaning(
          partOfSpeech: cache.partOfSpeech ?? '',
          definitions: defs,
        ),
      ],
    );
  }

  static WordDefinition _parseApiResponse(Map<String, dynamic> json) {
    final word = json['word'] as String? ?? '';
    String? phonetic;
    final phonetics = json['phonetics'] as List<dynamic>? ?? [];
    String? audioUrl;
    for (final ph in phonetics) {
      final phMap = ph as Map<String, dynamic>;
      final audio = phMap['audio'] as String? ?? '';
      final text = phMap['text'] as String?;
      if (text != null && text.isNotEmpty) {
        phonetic = text;
        if (audio.isNotEmpty) { audioUrl = audio; break; }
      }
    }
    if ((phonetic == null || phonetic.isEmpty) && json['phonetic'] != null) {
      phonetic = json['phonetic'] as String;
    }

    final origin = json['origin'] as String?;
    final meaningsJson = json['meanings'] as List<dynamic>? ?? [];
    final meanings = meaningsJson.map((m) {
      final mMap = m as Map<String, dynamic>;
      final partOfSpeech = mMap['partOfSpeech'] as String? ?? '';
      final defsJson = mMap['definitions'] as List<dynamic>? ?? [];
      final definitions = defsJson.map((d) {
        final dMap = d as Map<String, dynamic>;
        return Definition(
          definition: dMap['definition'] as String? ?? '',
          example: dMap['example'] as String?,
          synonyms: (dMap['synonyms'] as List<dynamic>?)
              ?.map((e) => e.toString()).toList() ?? [],
          antonyms: (dMap['antonyms'] as List<dynamic>?)
              ?.map((e) => e.toString()).toList() ?? [],
        );
      }).toList();
      return Meaning(partOfSpeech: partOfSpeech, definitions: definitions);
    }).toList();

    return WordDefinition(
      word: word,
      phonetic: phonetic,
      phoneticAudioUrl: audioUrl,
      origin: origin,
      meanings: meanings,
    );
  }
}