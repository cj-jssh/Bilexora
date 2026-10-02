import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/router.dart';
import '../../core/database/library_database.dart';
import '../../core/services/dictionary_manager.dart';
import '../../core/state/dictionary_providers.dart';
import '../home/home_screen.dart';
import 'translation_engine_screen.dart';
import 'dictionary_screen.dart';

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
  // 运行时读取的构建版本号 (与 pubspec.yaml 的 version 保持一致)
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadAllSettings();
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

  Future<void> _saveBilingualEnabled(bool value) async {
    await _db.setSetting('bilingual_enabled', value ? '1' : '0');
  }

  Future<void> _saveNativeLanguage(String value) async {
    await _db.setSetting('native_language', value);
  }

  Future<void> _saveBilingualLearning(String value) async {
    await _db.setSetting('bilingual_learning', value);
  }

  Future<void> _saveBilingualLayout(String value) async {
    await _db.setSetting('bilingual_layout', value);
  }

  Future<void> _saveBilingualShowMode(String value) async {
    await _db.setSetting('bilingual_show_mode', value);
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

          // 母语
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('我的母语'),
            subtitle: Text(languageNames[ref.watch(nativeLanguageProvider)] ?? '中文'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(
              context,
              ref.watch(nativeLanguageProvider),
              (lang) {
                ref.read(nativeLanguageProvider.notifier).state = lang;
                _saveNativeLanguage(lang);
              },
            ),
          ),
          const Divider(),

          // 双语阅读
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('双语阅读'),
            subtitle: Text(
              ref.watch(bilingualEnabledProvider) ? '已开启' : '已关闭',
              style: TextStyle(
                color: ref.watch(bilingualEnabledProvider)
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBilingualSettings(context, ref),
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
            subtitle: const Text('计算中...'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            onTap: () {},
          ),
          const Divider(),

          // 关于
          _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: Text(_appVersion.isEmpty ? '1.0.3' : _appVersion),
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

  void _showLanguagePicker(BuildContext context, String current, ValueChanged<String> onSelected) {
    final entries = languageNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择语言'),
        children: [
          for (final entry in entries)
            RadioListTile<String>(
              title: Text(entry.value),
              subtitle: Text(entry.key.toUpperCase()),
              value: entry.key,
              groupValue: current,
              onChanged: (value) {
                if (value != null) {
                  onSelected(value);
                  Navigator.pop(ctx);
                }
              },
            ),
        ],
      ),
    );
  }

  void _showBilingualSettings(BuildContext context, WidgetRef ref) {
    final layoutOptions = {
      'alternating': '交替显示',
      'paragraph': '段落后显示',
      'side_by_side': '左右分栏',
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('双语阅读', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 启用开关
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用双语阅读'),
                subtitle: const Text('阅读时显示原文与译文'),
                value: ref.watch(bilingualEnabledProvider),
                onChanged: (value) {
                  ref.read(bilingualEnabledProvider.notifier).state = value;
                  _saveBilingualEnabled(value);
                  setSheetState(() {});
                },
              ),
              // 译文展示方式
              const SizedBox(height: 4),
              const Text('译文展示', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('立即展示'),
                subtitle: const Text('译文直接跟随原文显示'),
                value: 'immediate',
                groupValue: ref.watch(bilingualShowModeProvider),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(bilingualShowModeProvider.notifier).state = value;
                    _saveBilingualShowMode(value);
                    setSheetState(() {});
                  }
                },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('点击展示'),
                subtitle: const Text('点击原文区域后才显示译文'),
                value: 'on_tap',
                groupValue: ref.watch(bilingualShowModeProvider),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(bilingualShowModeProvider.notifier).state = value;
                    _saveBilingualShowMode(value);
                    setSheetState(() {});
                  }
                },
              ),
              const Divider(),
              // 学习语言
              const Text('学习语言', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.menu_book, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(languageNames[ref.watch(bilingualLearningLanguageProvider)] ?? 'English'),
                  ),
                  TextButton(
                    onPressed: () {
                      _showLanguagePicker(
                        context,
                        ref.read(bilingualLearningLanguageProvider),
                        (lang) {
                          ref.read(bilingualLearningLanguageProvider.notifier).state = lang;
                          _saveBilingualLearning(lang);
                        },
                      );
                    },
                    child: const Text('更改'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 阅读习惯
              const Text('阅读习惯', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '默认书籍原文语言为学习语言。如果书籍语言与母语一致，则会自动反转：将译文作为原文，书籍原文做译文展示。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ...layoutOptions.entries.map((entry) => RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value),
                subtitle: Text(_layoutSubtitle(entry.key)),
                value: entry.key,
                groupValue: ref.watch(bilingualLayoutProvider),
                onChanged: (value) {
                  if (value != null) {
                    ref.read(bilingualLayoutProvider.notifier).state = value;
                    _saveBilingualLayout(value);
                    setSheetState(() {});
                  }
                },
              )),
            ],
          ),
        ),
      ),
      ),
    );
  }

  String _layoutSubtitle(String layout) {
    switch (layout) {
      case 'alternating':
        return '原文与译文交替出现';
      case 'paragraph':
        return '每段原文后紧跟译文';
      case 'side_by_side':
        return '原文在左，译文在右';
      default:
        return '';
    }
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