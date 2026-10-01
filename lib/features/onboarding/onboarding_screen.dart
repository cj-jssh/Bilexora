import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/library_database.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/translation/local_translation_service.dart';

/// 首次启动引导页
///
/// 流程:
///   1. 选择学习语言和母语
///   2. 后台下载翻译引擎模型 + 部署词库（不阻塞用户）
///   3. 直接进入主应用，下载在后台进行
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String _learningLang = 'en';
  String _nativeLang = 'zh';

  void _onLanguageSelected() {
    final db = LibraryDatabase();

    // 保存语言设置
    db.setSetting('native_language', _nativeLang);
    db.setSetting('bilingual_learning', _learningLang);

    // 更新 Provider
    ref.read(nativeLanguageProvider.notifier).state = _nativeLang;
    ref.read(bilingualLearningLanguageProvider.notifier).state = _learningLang;

    // 标记首次启动完成
    db.setSetting('first_launch_complete', '1');

    // 在后台启动模型下载（不 await，不阻塞用户）
    _startBackgroundDownload();

    // 直接进入主页，不等下载完成
    context.go('/home');
  }

  void _startBackgroundDownload() async {
    final db = LibraryDatabase();
    final langsToCheck = <String>{'zh'};
    if (_nativeLang != 'en') langsToCheck.add(_nativeLang);
    if (_learningLang != 'en') langsToCheck.add(_learningLang);

    final langName = languageNames[_learningLang] ?? _learningLang;
    final nativeName = languageNames[_nativeLang] ?? _nativeLang;

    for (final lang in langsToCheck) {
      final displayName = languageNames[lang] ?? lang;
      try {
        LocalTranslationService.markDownloadPending(lang);
        if (await LocalTranslationService.needsDownload(lang)) {
          await LocalTranslationService.downloadLanguageModel(lang);
        }
        final installed = await db.getSetting('installed_languages');
        final set = (installed ?? '').split(',').where((l) => l.isNotEmpty).toSet();
        set.add(lang);
        await db.setSetting('installed_languages', set.join(','));
        // 发送通知：模型下载完成
        await db.addNotification(
          type: 'download',
          title: '翻译包下载完成',
          body: '「$displayName」语言翻译包已下载就绪',
        );
      } catch (e) {
        debugPrint('后台下载 $lang 模型失败: $e');
        await db.addNotification(
          type: 'download_error',
          title: '翻译包下载失败',
          body: '「$displayName」语言翻译包下载失败，请前往设置重试',
        );
      } finally {
        LocalTranslationService.markDownloadComplete(lang);
      }
    }

    // 预加载模型
    try {
      await LocalTranslationService.ensureInitialized();
      for (final lang in langsToCheck) {
        await LocalTranslationService.preloadLanguage(lang);
      }
      await db.setSetting('builtin_translation_ready', '1');
      debugPrint('后台: 所有语言模型已加载就绪');
      await db.addNotification(
        type: 'setup_complete',
        title: '离线翻译引擎就绪',
        body: '已支持 $langName ↔ $nativeName 离线翻译，无需联网即可使用',
      );
    } catch (e) {
      debugPrint('后台加载模型失败: $e');
      await db.addNotification(
        type: 'setup_error',
        title: '翻译引擎初始化失败',
        body: '离线翻译引擎加载失败，部分翻译功能可能不可用',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Logo / 标题 ──
              Icon(Icons.auto_stories, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Bilexora',
                style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('离线阅读 & 语言学习',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),

              const Spacer(flex: 1),

              // ── 语言选择 ──
              _buildLanguageSelection(theme),

              const Spacer(flex: 2),

              // ── 底部提示 ──
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  '选择后即可开始使用，翻译模型将在后台自动下载',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelection(ThemeData theme) {
    return Column(
      children: [
        Text('欢迎使用！请选择您的语言设置',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text('后续可在设置中随时更改',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),

        // 学习语言
        _LangPicker(
          label: '学习语言',
          value: _learningLang,
          onChanged: (v) => setState(() => _learningLang = v),
          theme: theme,
        ),
        const SizedBox(height: 20),

        // 母语
        _LangPicker(
          label: '母语',
          value: _nativeLang,
          onChanged: (v) => setState(() => _nativeLang = v),
          theme: theme,
        ),
        const SizedBox(height: 40),

        FilledButton(
          onPressed: _onLanguageSelected,
          child: const Text('开始使用', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

class _LangPicker extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final ThemeData theme;

  const _LangPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final entries = languageNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text('${e.value} (${e.key.toUpperCase()})'),
          )).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}