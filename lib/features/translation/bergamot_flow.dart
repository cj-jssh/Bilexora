import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state.dart';
import '../settings/settings_screen.dart';
import 'local_translation_service.dart';

/// 解析本地引擎（Bergamot）的翻译方向。
///
/// 书籍语言 == 母语 → 翻成学习语言；否则 → 翻成母语。
/// Bergamot 仅支持 EN ↔ X：两个方向都不是英语时回退为经英语中转
/// （zh→X 会拆成 zh→en + en→X 两段）。
(String source, String target) resolveLocalDirection({
  required String bookLanguage,
  required String nativeLanguage,
  required String learningLanguage,
}) {
  final target = bookLanguage == nativeLanguage ? learningLanguage : nativeLanguage;
  return (bookLanguage, target);
}

/// 确保本地翻译模型可用，需要时引导用户下载。
///
/// 返回 true = 模型可用（含已是英语或已安装）；
/// 返回 false = 用户取消或下载失败，调用方应直接返回。
Future<bool> ensureBergamotModel(
  BuildContext context,
  WidgetRef ref,
  String lang,
) async {
  if (lang == 'en') return true;
  if (!await LocalTranslationService.needsDownload(lang)) return true;
  if (!context.mounted) return false;

  // 检查是否正在后台下载
  if (LocalTranslationService.isDownloadPending(lang)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('翻译模型文件正在后台下载中，请稍后再试'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
    return false;
  }

  // 下载确认
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('下载「${languageNames[lang] ?? lang}」翻译包'),
      content: const Text('需要在设备端下载翻译语言包（约30MB），是否现在下载？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('下载')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  // 模态下载中
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在下载翻译包...'),
        ],
      ),
    ),
  );
  await LocalTranslationService.downloadLanguageModel(lang);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

  // downloadLanguageModel 内部吞错（仅回调 onError），
  // 以下载结果为准判断是否成功
  final ok = await LocalTranslationService.isLanguageModelDownloaded(lang);
  if (ok) ref.read(installedLangsProvider.notifier).add(lang);
  return ok;
}
