import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/router.dart';
import '../../core/database/library_database.dart';
import '../../core/services/dictionary_manager.dart';
import '../../core/storage/storage_service.dart';
import '../../core/state/dictionary_providers.dart';
import '../home/home_screen.dart';
import 'translation_engine_screen.dart';
import 'dictionary_screen.dart';
import 'learning_settings_screen.dart';

/// 导入时是否自动翻译
final translateOnImportProvider = StateProvider<bool>((ref) {
  return false;
});

/// 母语设置
final nativeLanguageProvider = StateProvider<String>((ref) => 'zh');

/// 双语阅读设置
final bilingualEnabledProvider = StateProvider<bool>((ref) => false);
final bilingualLearningLanguageProvider = StateProvider<String>((ref) => 'en');

/// 阅读习惯选项
final bilingualLayoutProvider = StateProvider<String>((ref) => 'alternating'); // alternating, paragraph, side_by_side

/// 译文展示方式：immediate 立即展示，on_tap 点击后展示
final bilingualShowModeProvider = StateProvider<String>((ref) => 'immediate');

const Map<String, String> languageNames = {
  'zh': '中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'ru': 'Русский',
  'ar': 'العربية',
  'pt': 'Português',
  'it': 'Italiano',
  'vi': 'Tiếng Việt',
  'th': 'ภาษาไทย',
};

/// 设置屏幕
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final LibraryDatabase _db = LibraryDatabase();
  final StorageService _storage = StorageService();
  // 运行时读取的构建版本号 (与 pubspec.yaml 的 version 保持一致)
  String _appVersion = '';
  // 存储用量（字节）与加载状态
  int _storageBytes = 0;
  bool _storageLoading = true;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadAllSettings();
    _loadStorageUsage();
  }

  /// 异步计算存储用量
  Future<void> _loadStorageUsage() async {
    setState(() => _storageLoading = true);
    try {
      final (total, _) = await _storage.appUsageBytes();
      if (mounted) {
        setState(() {
          _storageBytes = total;
          _storageLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _storageLoading = false);
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // 读取失败时保留空串, 兜底显示 pubspec 同步的版本
    }
  }

  Future<void> _loadAllSettings() async {
    final translateValue = await _db.getSetting('translate_on_import');
    if (translateValue != null) {
      ref.read(translateOnImportProvider.notifier).state = translateValue == '1';
    }
    final bilingualValue = await _db.getSetting('bilingual_enabled');
    if (bilingualValue != null) {
      ref.read(bilingualEnabledProvider.notifier).state = bilingualValue == '1';
    }
    final nativeValue = await _db.getSetting('native_language');
    if (nativeValue != null) {
      ref.read(nativeLanguageProvider.notifier).state = nativeValue;
    }
    final learningValue = await _db.getSetting('bilingual_learning');
    if (learningValue != null) {
      ref.read(bilingualLearningLanguageProvider.notifier).state = learningValue;
    }
    final layoutValue = await _db.getSetting('bilingual_layout');
    if (layoutValue != null) {
      ref.read(bilingualLayoutProvider.notifier).state = layoutValue;
    }
    final showModeValue = await _db.getSetting('bilingual_show_mode');
    if (showModeValue != null) {
      ref.read(bilingualShowModeProvider.notifier).state = showModeValue;
    }
  }

  Future<void> _saveTranslateOnImport(bool value) async {
    await _db.setSetting('translate_on_import', value ? '1' : '0');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final translateOnImport = ref.watch(translateOnImportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 外观
          _SectionHeader(title: '外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('主题'),
            subtitle: Text(_themeModeName(themeMode)),
            onTap: () => _showThemePicker(context, ref),
          ),
          const Divider(),

          // 阅读（学习菜单项，跳转学习设置页）
          _SectionHeader(title: '阅读'),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('学习'),
            subtitle: const Text('母语 / 双语阅读 / 逐句精听'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LearningSettingsScreen(),
              ),
            ),
          ),
          const Divider(),

          // 翻译
          _SectionHeader(title: '翻译'),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('翻译引擎管理'),
            subtitle: Text(_engineSummary(ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showTranslationEngineSheet(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('词典管理'),
            subtitle: Text(_dictSummary(ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DictionaryScreen(),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('导入时翻译'),
            subtitle: const Text('导入书籍后自动调用翻译服务'),
            value: translateOnImport,
            onChanged: (value) {
              ref.read(translateOnImportProvider.notifier).state = value;
              _saveTranslateOnImport(value);
            },
          ),
          const Divider(),

          // 目标
          _SectionHeader(title: '目标'),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('每日阅读时长'),
            subtitle: Text('${ref.watch(dailyReadingGoalProvider)} 分钟'),
            onTap: () => _showDailyGoalPicker(context, ref),
          ),
          const Divider(),

          // 存储
          _SectionHeader(title: '存储'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('存储用量'),
            subtitle: Text(
              _storageLoading ? '计算中...' : formatBytes(_storageBytes),
            ),
            onTap: _storageLoading ? null : _loadStorageUsage,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: _clearingCache ? const Text('正在清除...') : const Text('清理词典缓存与临时文件'),
            onTap: _clearingCache ? null : _confirmClearCache,
          ),
          const Divider(),

          // 关于
          _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: Text(_appVersion.isEmpty ? '1.2.2' : _appVersion),
          ),
        ],
      ),
    );
  }

  String _themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择主题'),
        children: [
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              title: Text(_themeModeName(mode)),
              value: mode,
              groupValue: ref.read(themeModeProvider),
              onChanged: (value) {
                if (value != null) {
                  ref.read(themeModeProvider.notifier).state = value;
                  Navigator.pop(ctx);
                }
              },
            ),
        ],
      ),
    );
  }

  String _engineSummary(WidgetRef ref) {
    final active = ref.watch(activeTranslationEngineProvider);
    return active?.name ?? '未设置';
  }

  String _dictSummary(WidgetRef ref) {
    final sources = ref.watch(dictSourcesProvider);
    if (sources.isEmpty) return '仅内置词典';
    final sqliteCount = sources.where((s) => s.type == DictSourceType.sqlite).length;
    final mdxCount = sources.where((s) => s.type == DictSourceType.mdx).length;
    final parts = <String>[];
    if (sqliteCount > 0) parts.add('SQLite×$sqliteCount');
    if (mdxCount > 0) parts.add('MDX×$mdxCount');
    return parts.join('、');
  }

  void _showTranslationEngineSheet(BuildContext context, WidgetRef ref) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const TranslationEngineScreen(),
    ));
  }

  /// 清除缓存确认并执行
  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('将清理词典缓存与临时文件（不影响书籍、阅读进度和生词本）。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _clearingCache = true);
    try {
      final released = await _storage.clearCache();
      await _loadStorageUsage();
      if (mounted) {
        setState(() => _clearingCache = false);
        final msg = released > 0
            ? '已清除缓存（释放 ${formatBytes(released)}）'
            : '已清除缓存';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _clearingCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('清除失败，请稍后重试'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showDailyGoalPicker(BuildContext context, WidgetRef ref) {
    final current = ref.read(dailyReadingGoalProvider);
    int selected = current;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          title: const Text('每日阅读目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$selected 分钟',
                  style: Theme.of(ctx).textTheme.headlineMedium),
              Slider(
                value: selected.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                label: '$selected 分钟',
                onChanged: (v) => setSheetState(() => selected = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(onPressed: () {
              ref.read(dailyReadingGoalProvider.notifier).state = selected;
              Navigator.pop(ctx);
            }, child: const Text('确定')),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}