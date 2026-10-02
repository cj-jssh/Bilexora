import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/storage/translation_file.dart';
import '../../core/database/library_database.dart';
import '../translation/translation_task_manager.dart';
import '../../core/state/app_state.dart';
import 'library_screen.dart';

import 'package:path/path.dart' as p;

/// 已持久化的翻译状态（从 SQLite 读取）
class PersistedTranslation {
  final String bookId;
  final String bookTitle;
  final String language;
  final int sentenceCount;
  final String engineId;
  final String status;
  final DateTime updatedAt;

  PersistedTranslation({
    required this.bookId,
    required this.bookTitle,
    required this.language,
    required this.sentenceCount,
    required this.engineId,
    required this.status,
    required this.updatedAt,
  });

  factory PersistedTranslation.fromMap(Map<String, dynamic> map) {
    return PersistedTranslation(
      bookId: map['book_id'] as String,
      bookTitle: map['book_title'] as String? ?? '',
      language: map['language'] as String,
      sentenceCount: map['sentence_count'] as int? ?? 0,
      engineId: map['engine_id'] as String? ?? '',
      status: map['status'] as String? ?? 'completed',
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : DateTime.now(),
    );
  }
}

/// 从 SQLite 和磁盘翻译文件加载所有已完成的翻译
final persistedTranslationsProvider = FutureProvider<List<PersistedTranslation>>((ref) async {
  final db = LibraryDatabase();
  final rows = await db.getAllTranslationStatus();
  // 将同一本书的多个语言合并为一个条目，取最新的
  final merged = <String, PersistedTranslation>{};
  for (final row in rows) {
    final pt = PersistedTranslation.fromMap(row);
    final existing = merged[pt.bookId];
    if (existing == null || pt.updatedAt.isAfter(existing.updatedAt)) {
      merged[pt.bookId] = pt;
    }
  }
  final list = merged.values.toList();
  list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return list;
});

/// 扫描书籍目录下的 content_*.dat 文件，同步 DB 翻译状态：
///   1. 磁盘有文件但 DB 无记录 → 自动补全
///   2. DB 有记录但磁盘无对应文件 → 删除过期状态
final scannedTranslationsProvider = FutureProvider<List<PersistedTranslation>>((ref) async {
  final libraryPath = ref.read(libraryPathProvider);
  final db = LibraryDatabase();
  final books = await db.getAllBooks();
  final result = <PersistedTranslation>[];
  for (final book in books) {
    final fm = TranslationFileManager(p.join(libraryPath, 'books', book.id), bookId: book.id);
    final langs = await fm.listAvailableLanguages();
    for (final lang in langs) {
      final sentenceCount = await fm.translationSentenceCount(lang);
      if (sentenceCount == 0) continue;
      final engines = await fm.listEnginesForLanguage(lang);
      // 检查 DB 中是否已有记录
      final existingRows = await db.getBookTranslationStatus(book.id);
      final hasLang = existingRows.any((r) => r['language'] == lang);
      if (!hasLang) {
        // 自动补全
        final engineIds = engines.map((e) => e.engineId).toSet();
        await db.saveTranslationStatus(
          bookId: book.id,
          bookTitle: book.title,
          language: lang,
          sentenceCount: sentenceCount,
          engineId: engineIds.firstOrNull ?? 'unknown',
        );
      }
    }
    // 反向检查：DB 中有记录但磁盘上已无对应翻译文件 → 删除过期状态
    final bookRows = await db.getBookTranslationStatus(book.id);
    final staleRows = bookRows.where((r) => !langs.contains(r['language'])).toList();
    for (final row in staleRows) {
      await db.deleteTranslationStatus(book.id, row['language'] as String);
    }
    // 重新从 DB 读取（排除刚删除的过期记录）
    final freshRows = await db.getBookTranslationStatus(book.id);
    for (final row in freshRows) {
      final pt = PersistedTranslation.fromMap(row);
      final existingIdx = result.indexWhere((e) => e.bookId == pt.bookId);
      if (existingIdx >= 0) {
        if (pt.updatedAt.isAfter(result[existingIdx].updatedAt)) {
          result[existingIdx] = pt;
        }
      } else {
        result.add(pt);
      }
    }
  }
  result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
});

class TranslationManagementScreen extends ConsumerWidget {
  const TranslationManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(translationTaskManagerProvider);
    final active = tasks.values
        .where((t) => t.status == TranslationTaskStatus.translating || t.status == TranslationTaskStatus.queued)
        .toList();
    final failed = tasks.values
        .where((t) => t.status == TranslationTaskStatus.failed)
        .toList();

    // 从 SQLite 读取持久化的翻译记录。
    // 完成即落库，因此管理页统一由持久化记录展示「已完成」，无需内存任务。
    // 进入页面时刷新一次：磁盘上可能有未持久化状态的译文文件（如取消翻译后的已完成部分），
    // 需要重新扫描补全 DB 记录；invalidate 会触发重扫，已有记录也不会重复插入（自动补全有判重）
    Future.microtask(() => ref.invalidate(scannedTranslationsProvider));
    final persistedAsync = ref.watch(scannedTranslationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('翻译管理')),
      body: persistedAsync.when(
        data: (persisted) {
          final hasActive = active.isNotEmpty;
          final hasPersisted = persisted.isNotEmpty;
          final hasFailed = failed.isNotEmpty;

          if (!hasActive && !hasPersisted && !hasFailed) {
            return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.translate, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('暂无翻译', style: TextStyle(fontSize: 18, color: Colors.grey)),
              SizedBox(height: 8),
              Text('在书库中选择「翻译全本」开始', style: TextStyle(color: Colors.grey)),
            ]));
          }

          return ListView(children: [
            // 翻译中
            if (hasActive) ...[
              _SectionHeader(title: '翻译中', count: active.length),
              ...active.map((t) => _ActiveTaskCard(task: t)),
              const SizedBox(height: 8),
            ],
            // 已完成（全部来自持久化记录）
            if (hasPersisted) ...[
              _SectionHeader(title: '已完成', count: persisted.length),
              ...persisted.map((pt) => _PersistedTaskCard(persisted: pt)),
              const SizedBox(height: 8),
            ],
            // 失败
            if (hasFailed) ...[
              _SectionHeader(title: '失败', count: failed.length),
              ...failed.map((t) => _FailedTaskCard(task: t)),
            ],
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          // 即使扫描失败也展示内存中的数据
          final hasActive = active.isNotEmpty;
          final hasFailed = failed.isNotEmpty;

          if (!hasActive && !hasFailed) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('加载失败: $e', style: const TextStyle(color: Colors.grey)),
            ]));
          }

          return ListView(children: [
            if (hasActive) ...[
              _SectionHeader(title: '翻译中', count: active.length),
              ...active.map((t) => _ActiveTaskCard(task: t)),
              const SizedBox(height: 8),
            ],

            if (hasFailed) ...[
              _SectionHeader(title: '失败', count: failed.length),
              ...failed.map((t) => _FailedTaskCard(task: t)),
            ],
          ]);
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
        ),
      ]),
    );
  }
}

class _ActiveTaskCard extends ConsumerWidget {
  final TranslationTask task;
  const _ActiveTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusText = task.status == TranslationTaskStatus.queued ? '等待中…' : '${(task.progress * 100).round()}%';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(value: task.progress > 0 ? task.progress : null, strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(task.bookTitle, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text(statusText, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: const Text('取消', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error, padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () {
                ref.read(translationTaskManagerProvider.notifier).cancelTask(task.bookId);
                ref.read(translationProgressProvider(task.bookId).notifier).state = null;
              },
            ),
          ]),
          if (task.status == TranslationTaskStatus.translating) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: task.progress.clamp(0.0, 1.0), minHeight: 4),
            ),
          ],
        ]),
      ),
    );
  }
}

/// 持久化的翻译记录卡片
class _PersistedTaskCard extends ConsumerWidget {
  final PersistedTranslation persisted;
  const _PersistedTaskCard({required this.persisted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = '${persisted.updatedAt.month}/${persisted.updatedAt.day} ${persisted.updatedAt.hour}:${persisted.updatedAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.translate, color: Colors.blue),
        title: Text(persisted.bookTitle),
        subtitle: Text('已翻译 ${persisted.sentenceCount} 句 ($dateStr)',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.pushNamed('translationDetail', pathParameters: {'bookId': persisted.bookId}),
      ),
    );
  }
}

class _FailedTaskCard extends ConsumerWidget {
  final TranslationTask task;
  const _FailedTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: Text(task.bookTitle),
        subtitle: Text(task.error ?? '未知错误', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.error)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => ref.read(translationTaskManagerProvider.notifier).cancelTask(task.bookId),
        ),
      ),
    );
  }
}