import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/library_database.dart';
import 'local_translation_service.dart';

/// 翻译任务状态
/// 完成的任务会在落库后被标记移除，不再长期存在于内存中。
enum TranslationTaskStatus { queued, translating, failed, cancelled }

/// 翻译任务描述
class TranslationTask {
  final String bookId;
  final String bookTitle;
  final int totalSentences;
  TranslationTaskStatus status;
  double progress;
  String? error;

  TranslationTask({
    required this.bookId,
    required this.bookTitle,
    required this.totalSentences,
    this.status = TranslationTaskStatus.queued,
    this.progress = 0.0,
    this.error,
  });
}

/// 翻译任务管理器：按 bookId 跟踪批量翻译任务状态
class TranslationTaskManager extends StateNotifier<Map<String, TranslationTask>> {
  TranslationTaskManager() : super({});

  void addTask(TranslationTask task) => state = {...state, task.bookId: task};

  /// 翻译完成即从内存任务中移除：结果已落库，持久化记录由
  /// 翻译管理页从 DB 扫描展示，内存不需要保留「已完成」任务。
  void markCompleted(String bookId) {
    if (!state.containsKey(bookId)) return;
    state = {...state}..remove(bookId);
  }

  void markFailed(String bookId, String error) {
    final task = state[bookId];
    if (task == null) return;
    task.status = TranslationTaskStatus.failed;
    task.error = error;
    state = {...state, bookId: task};
    // 发送通知
    LibraryDatabase().addNotification(
      type: 'translation_failed',
      title: '翻译失败',
      body: '「${task.bookTitle}」翻译失败: $error',
      bookId: bookId,
    );
  }

  void cancelTask(String bookId) {
    final task = state[bookId];
    if (task == null) return;
    LocalTranslationService.cancelBook(bookId);
    task.status = TranslationTaskStatus.cancelled;
    state = {...state, bookId: task};
    // 发送通知
    LibraryDatabase().addNotification(
      type: 'translation_cancelled',
      title: '翻译已取消',
      body: '「${task.bookTitle}」的翻译任务已取消',
      bookId: bookId,
    );
  }
}

final translationTaskManagerProvider =
    StateNotifierProvider<TranslationTaskManager, Map<String, TranslationTask>>(
        (ref) => TranslationTaskManager());
