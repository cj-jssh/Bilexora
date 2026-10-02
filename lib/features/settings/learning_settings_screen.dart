import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/library_database.dart';
import 'settings_screen.dart'; // 复用 languageNames、母语/双语 providers

/// 逐句精听设置：开启后阅读时逐句朗读
final sentenceListeningEnabledProvider = StateProvider<bool>((ref) => false);
/// 逐句精听朗读语速（0.0 ~ 1.0）
final sentenceListeningRateProvider = StateProvider<double>((ref) => 0.4);
/// 逐句精听是否自动连播
final sentenceListeningAutoPlayProvider = StateProvider<bool>((ref) => true);

/// 学习设置页：母语 / 双语阅读 / 逐句精听
class LearningSettingsScreen extends ConsumerStatefulWidget {
  const LearningSettingsScreen({super.key});

  @override
  ConsumerState<LearningSettingsScreen> createState() => _LearningSettingsScreenState();
}

class _LearningSettingsScreenState extends ConsumerState<LearningSettingsScreen> {
  final LibraryDatabase _db = LibraryDatabase();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final value = await _db.getSetting('sentence_listening_enabled');
    if (value != null) {
      ref.read(sentenceListeningEnabledProvider.notifier).state = value == '1';
    }
    final rate = await _db.getSetting('sentence_listening_rate');
    if (rate != null) {
      ref.read(sentenceListeningRateProvider.notifier).state =
          double.tryParse(rate) ?? 0.4;
    }
    final auto = await _db.getSetting('sentence_listening_auto');
    if (auto != null) {
      ref.read(sentenceListeningAutoPlayProvider.notifier).state = auto == '1';
    }
  }

  Future<void> _saveListeningEnabled(bool v) =>
      _db.setSetting('sentence_listening_enabled', v ? '1' : '0');
  Future<void> _saveListeningRate(double v) =>
      _db.setSetting('sentence_listening_rate', v.toString());
  Future<void> _saveListeningAuto(bool v) =>
      _db.setSetting('sentence_listening_auto', v ? '1' : '0');

  Future<void> _saveNativeLanguage(String v) =>
      _db.setSetting('native_language', v);

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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用双语阅读'),
                  subtitle: const Text('阅读时显示原文与译文'),
                  value: ref.watch(bilingualEnabledProvider),
                  onChanged: (value) {
                    ref.read(bilingualEnabledProvider.notifier).state = value;
                    _db.setSetting('bilingual_enabled', value ? '1' : '0');
                    setSheetState(() {});
                  },
                ),
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
                      _db.setSetting('bilingual_show_mode', value);
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
                      _db.setSetting('bilingual_show_mode', value);
                      setSheetState(() {});
                    }
                  },
                ),
                const Divider(),
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
                            _db.setSetting('bilingual_learning', lang);
                          },
                        );
                      },
                      child: const Text('更改'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      _db.setSetting('bilingual_layout', value);
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

  @override
  Widget build(BuildContext context) {
    final listeningEnabled = ref.watch(sentenceListeningEnabledProvider);
    final listeningRate = ref.watch(sentenceListeningRateProvider);
    final listeningAuto = ref.watch(sentenceListeningAutoPlayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          // 母语
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('母语'),
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
          // 逐句精听
          SwitchListTile(
            secondary: const Icon(Icons.headphones_outlined),
            title: const Text('逐句精听'),
            subtitle: const Text('阅读时逐句朗读'),
            value: listeningEnabled,
            onChanged: (value) {
              ref.read(sentenceListeningEnabledProvider.notifier).state = value;
              _saveListeningEnabled(value);
            },
          ),
          if (listeningEnabled) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('朗读语速'),
              subtitle: Text('${(listeningRate * 100).round()}%'),
            ),
            Slider(
              value: listeningRate,
              min: 0.2,
              max: 0.7,
              divisions: 10,
              label: '${(listeningRate * 100).round()}%',
              onChanged: (v) {
                ref.read(sentenceListeningRateProvider.notifier).state = v;
                _saveListeningRate(v);
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('自动连播'),
              subtitle: const Text('一句读完后自动朗读下一句'),
              value: listeningAuto,
              onChanged: (value) {
                ref.read(sentenceListeningAutoPlayProvider.notifier).state = value;
                _saveListeningAuto(value);
              },
            ),
          ],
        ],
      ),
    );
  }
}