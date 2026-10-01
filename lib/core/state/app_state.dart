import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/library_database.dart';

/// 已下载的语言集合（启动时由 main 自动填充，语言管理页面读取）
final installedLangsProvider =
    StateNotifierProvider<InstalledLangsNotifier, Set<String>>((ref) {
  return InstalledLangsNotifier();
});

/// Each book's translation progress (0.0 to 1.0, null = not translating)
final translationProgressProvider = StateProvider.family<double?, String>((ref, bookId) => null);

class InstalledLangsNotifier extends StateNotifier<Set<String>> {
  InstalledLangsNotifier() : super({'zh', 'en'}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final db = LibraryDatabase();
      final languages = await db.getSetting('installed_languages');
      if (languages != null && languages.isNotEmpty) {
        // 合并 DB 数据，确保 zh/en 始终内置
        state = <String>{'zh', 'en'}..addAll(languages.split(','));
      }
    } catch (_) {}
  }

  Future<void> add(String lang) async {
    state = {...state, lang};
    final db = LibraryDatabase();
    await db.setSetting('installed_languages', state.join(','));
  }

  Future<void> remove(String lang) async {
    state = {...state}..remove(lang);
    final db = LibraryDatabase();
    await db.setSetting('installed_languages', state.join(','));
  }
}