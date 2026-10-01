import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'features/library/library_screen.dart';
import 'core/database/library_database.dart';
import 'features/translation/local_translation_service.dart';
import 'features/settings/settings_screen.dart';
import 'core/services/dictionary_manager.dart';
import 'core/state/dictionary_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final libraryPath = p.join(dir.path, 'library');

  // 后台启动任务：初始化 Bergamot + 检查并下载母语/学习语言模型
  _startupModelCheck();
  // 部署内置离线词库
  _deployBuiltinDict();

  runApp(
    ProviderScope(
      overrides: [
        libraryPathProvider.overrideWithValue(libraryPath),
      ],
      child: const BilexoraApp(),
    ),
  );
}

Future<void> _startupModelCheck() async {
  try {
    final db = LibraryDatabase();

    // 首次启动还没完成引导 → 跳过（引导页会处理）
    final firstLaunch = await db.getSetting('first_launch_complete');
    if (firstLaunch != '1') {
      debugPrint('Startup: 首次引导尚未完成，跳过后台下载');
      return;
    }

    String nativeLang = 'zh';
    String learningLang = 'en';
    try {
      final native = await db.getSetting('native_language');
      if (native != null && native.isNotEmpty) nativeLang = native;
      final learning = await db.getSetting('bilingual_learning');
      if (learning != null && learning.isNotEmpty) learningLang = learning;
    } catch (_) {}

    // 始终检查 zh（内置语言）和用户语言是否需要下载
    final langsToCheck = <String>{'zh'};
    if (nativeLang != 'en') langsToCheck.add(nativeLang);
    if (learningLang != 'en') langsToCheck.add(learningLang);

    for (final lang in langsToCheck) {
      final displayName = languageNames[lang] ?? lang;
      try {
        if (await LocalTranslationService.needsDownload(lang)) {
          debugPrint('Startup: downloading model for $lang...');
          await LocalTranslationService.downloadLanguageModel(lang);
          debugPrint('Startup: downloaded model for $lang');
          await db.addNotification(
            type: 'download',
            title: '翻译包下载完成',
            body: '「$displayName」语言翻译包已下载就绪',
          );
        }
        // 标记为已安装（即使已存在也确保 DB 记录）
        final installed = await db.getSetting('installed_languages');
        final set = (installed ?? '').split(',').where((l) => l.isNotEmpty).toSet();
        set.add(lang);
        await db.setSetting('installed_languages', set.join(','));
      } catch (e) {
        debugPrint('Startup: failed to download $lang: $e');
        await db.addNotification(
          type: 'download_error',
          title: '翻译包下载失败',
          body: '「$displayName」语言翻译包下载失败，请前往设置重试',
        );
      }
    }

    // 预热 Bergamot 引擎并预加载模型
    try {
      await LocalTranslationService.ensureInitialized();
      debugPrint('Startup: Bergamot engine initialized');

      // 预加载母语和学习语言的模型（双向 en↔X）
      for (final lang in langsToCheck) {
        try {
          await LocalTranslationService.preloadLanguage(lang);
          debugPrint('Startup: preloaded model for $lang');
        } catch (e) {
          debugPrint('Startup: failed to preload $lang: $e');
        }
      }
    } catch (e) {
      debugPrint('Startup: Bergamot init failed: $e');
    }
  } catch (e) {
    debugPrint('Startup model check failed: $e');
  }
}

/// 部署内置 ECDICT 离线词库
///
/// assets/core.db.gz 在首次启动时解压到外部词典目录，
/// 并自动注册为第一个 DictSource，让用户开箱即用。
///
/// 如果 asset 文件不存在（尚未构建词库），则静默跳过，
/// app 仍可正常使用，用户可自行导入外部词典。
Future<void> _deployBuiltinDict() async {
  try {
    final exists = await _assetExists('assets/core.db.gz');
    if (!exists) {
      debugPrint('[内置词典] asset 不存在，跳过部署');
      return;
    }
    final dir = await DictFileManager.getDictsDir();
    final destPath = p.join(dir.path, 'core.sqlite');
    final destFile = File(destPath);

    // 已部署过且版本匹配 → 跳过
    final db = LibraryDatabase();
    final deployed = await db.getSetting('builtin_dict_deployed');
    if (deployed == '1' && await destFile.exists()) {
      return;
    }

    debugPrint('[内置词典] 正在部署内置词库...');
    final (bool success, int entryCount) = await _deployDictFromAsset(
      'assets/core.db.gz',
      destPath,
    );

    if (!success) {
      debugPrint('[内置词典] 部署失败');
      return;
    }

    debugPrint('[内置词典] 部署完成: $entryCount 词条');

    // 自动注册到词典配置
    final sources = await DictSourcePersistence().load();
    // 检查是否已存在（防止重复注册）
    final alreadyExists = sources.any((s) => s.id == 'builtin_core');
    if (!alreadyExists) {
      final source = DictSource(
        id: 'builtin_core',
        name: 'ECDICT 核心词典',
        type: DictSourceType.sqlite,
        filePath: destPath,
        language: 'en',
        sortOrder: 0, // 最优先
        entryCount: entryCount,
        description: '内置英汉词典 ($entryCount 词条)',
      );
      final newSources = [source, ...sources];
      await DictSourcePersistence().save(newSources);
      // 动态加载
      await DictionaryManager().addSource(source);
      // 通知用户
      await db.addNotification(
        type: 'dictionary',
        title: '离线词典已部署',
        body: '内置英汉词典 ($entryCount 词条) 已就绪，阅读时点击单词即可查词',
      );
    }

    await db.setSetting('builtin_dict_deployed', '1');
  } catch (e) {
    debugPrint('[内置词典] 部署异常: $e');
  }
}

/// 检查 asset 文件是否存在（不会在 pubspec.yaml 注册时崩溃）
Future<bool> _assetExists(String path) async {
  try {
    await rootBundle.load(path);
    return true;
  } catch (_) {
    return false;
  }
}

/// 从 assets gzip 文件解压到目标路径
Future<(bool, int)> _deployDictFromAsset(String assetPath, String destPath) async {
  try {
    final byteData = await rootBundle.load(assetPath);
    final compressed = byteData.buffer.asUint8List();
    final decompressed = gzip.decode(compressed);
    await File(destPath).writeAsBytes(decompressed, flush: true);

    // 读取词条数
    int entryCount = 0;
    try {
      final db = await sqflite.openDatabase(destPath, readOnly: true);
      final result = await db.rawQuery('SELECT COUNT(*) AS c FROM words');
      entryCount = (result.first['c'] as num?)?.toInt() ?? 0;
      await db.close();
    } catch (_) {}

    return (true, entryCount);
  } catch (e) {
    debugPrint('[内置词典] 解压失败: $e');
    return (false, 0);
  }
}