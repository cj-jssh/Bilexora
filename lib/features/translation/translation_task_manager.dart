import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/library_database.dart';
import 'local_translation_service.dart';

/// 翻译任务状态
enum TranslationTaskStatus { queued, translating, completed, failed, cancelled }

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

  void markCompleted(String bookId) {
    final task = state[bookId];
    if (task == null) return;
    task.status = TranslationTaskStatus.completed;
    task.progress = 1.0;
    state = {...state, bookId: task};
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
