import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/library_database.dart';
import '../../core/services/dictionary_manager.dart';

// ══════════════════════════════════════════════════════
//  词典源持久化
// ══════════════════════════════════════════════════════

class DictSourcePersistence {
  static const _key = 'external_dict_sources';

  Future<void> save(List<DictSource> sources) async {
    final db = LibraryDatabase();
    final json = jsonEncode(sources.map((e) => e.toJson()).toList());
    await db.setSetting(_key, json);
  }

  Future<List<DictSource>> load() async {
    final db = LibraryDatabase();
    final json = await db.getSetting(_key);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => DictSource.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

// ══════════════════════════════════════════════════════
//  词典源列表 Provider（与翻译引擎架构平行）
// ══════════════════════════════════════════════════════

final dictSourcePersistenceProvider =
    Provider<DictSourcePersistence>((ref) => DictSourcePersistence());

final dictSourcesProvider = StateNotifierProvider<DictSourceListNotifier, List<DictSource>>((ref) {
  return DictSourceListNotifier(ref.read(dictSourcePersistenceProvider));
});

class DictSourceListNotifier extends StateNotifier<List<DictSource>> {
  final DictSourcePersistence _persistence;

  DictSourceListNotifier(this._persistence) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final saved = await _persistence.load();
    if (saved.isNotEmpty) {
      state = saved;
      // 初始化管理器
      await DictionaryManager().initialize(saved);
    }
  }

  Future<void> _persist() async {
    await _persistence.save(state);
    // 通知 DictionaryManager 重新加载
  }

  /// 添加词典源
  Future<void> add(DictSource source) async {
    state = [...state, source];
    await _persist();
    // 动态加载到管理器
    await DictionaryManager().addSource(source);
  }

  /// 移除词典源
  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
    await DictionaryManager().removeSource(id);
  }

  /// 重新排序
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    await _persist();
    // 重新初始化管理器
    await DictionaryManager().initialize(state);
  }

  bool contains(String id) => state.any((s) => s.id == id);
  int get length => state.length;
}

/// 获取第一个可用的词典源（用于查词模式默认行为）
final activeDictSourceProvider = Provider<DictSource?>((ref) {
  final sources = ref.watch(dictSourcesProvider);
  return sources.isNotEmpty ? sources.first : null;
});