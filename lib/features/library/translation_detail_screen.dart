import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/database/library_database.dart';
import '../../core/storage/translation_file.dart';
import '../../core/models/models.dart';
import '../settings/settings_screen.dart';
import 'library_screen.dart';
import 'translation_management_screen.dart' show scannedTranslationsProvider;

/// 给定书籍的翻译详情
final bookTranslationDetailProvider =
    FutureProvider.family<BookTranslationDetail, String>((ref, bookId) async {
  final db = LibraryDatabase();
  final book = await db.getBook(bookId);
  final libraryPath = ref.read(libraryPathProvider);
  final fm = TranslationFileManager(p.join(libraryPath, 'books', bookId), bookId: bookId);
  final langs = await fm.listAvailableLanguages();

  final languageEntries = <LanguageEntry>[];
  for (final lang in langs) {
    final engines = await fm.listEnginesForLanguage(lang);
    final sentenceCount = await fm.translationSentenceCount(lang);
    languageEntries.add(LanguageEntry(
      language: lang,
      sentenceCount: sentenceCount,
      engines: engines,
    ));
  }

  // 按语言名称排序
  languageEntries.sort((a, b) {
    final aName = languageNames[a.language] ?? a.language;
    final bName = languageNames[b.language] ?? b.language;
    return aName.compareTo(bName);
  });

  return BookTranslationDetail(
    book: book,
    languageEntries: languageEntries,
  );
});

class LanguageEntry {
  final String language;
  final int sentenceCount;
  final List<({String engineId, int count})> engines;
  LanguageEntry({
    required this.language,
    required this.sentenceCount,
    required this.engines,
  });
}

class BookTranslationDetail {
  final Book? book;
  final List<LanguageEntry> languageEntries;
  BookTranslationDetail({required this.book, required this.languageEntries});
}

/// 翻译详情页：展示某本书按语言归类的各引擎翻译记录
class TranslationDetailScreen extends ConsumerWidget {
  final String bookId;
  const TranslationDetailScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(bookTranslationDetailProvider(bookId));

    return Scaffold(
      appBar: AppBar(title: const Text('翻译详情')),
      body: detailAsync.when(
        data: (detail) {
          final entries = detail.languageEntries;

          if (entries.isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.translate, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('暂无翻译', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(detail.book?.title ?? '',
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.outline)),
              ]),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...entries.map((entry) => _LanguageCard(
                    bookId: bookId,
                    entry: entry,
                  )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _LanguageCard extends ConsumerStatefulWidget {
  final String bookId;
  final LanguageEntry entry;
  const _LanguageCard({
    required this.bookId,
    required this.entry,
  });

  @override
  ConsumerState<_LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends ConsumerState<_LanguageCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final langName = languageNames[widget.entry.language] ?? widget.entry.language;
    return Dismissible(
      key: ValueKey('lang-${widget.bookId}-${widget.entry.language}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteLanguage(context, ref),
      onDismissed: (_) => _performDeleteLanguage(ref, context, widget.bookId, widget.entry.language),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── 语言标题行（可点击展开/收起） ──
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language, size: 16,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(langName,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('共 ${widget.entry.sentenceCount} 句',
                    style: TextStyle(
                        fontSize: 13, color: Theme.of(context).colorScheme.outline)),
                const Spacer(),
                // 箭头图标（展开/收起）
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, size: 22,
                      color: Theme.of(context).colorScheme.outline),
                ),
              ]),
            ),
          ),
        // ── 展开的引擎列表 ──
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...widget.entry.engines.map((e) => _EngineRow(
                    bookId: widget.bookId,
                    language: widget.entry.language,
                    engineId: e.engineId,
                    count: e.count,
                  )),
            ]),
          ),
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        ]),
      ),
    );
  }

  Future<bool?> _confirmDeleteLanguage(BuildContext context, WidgetRef ref) async {
    final langName = languageNames[widget.entry.language] ?? widget.entry.language;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除整个语言版本'),
        content: Text('确定删除「$langName」的译文吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 引擎行（无删除图标，左滑删除）
class _EngineRow extends ConsumerWidget {
  final String bookId;
  final String language;
  final String engineId;
  final int count;
  const _EngineRow({
    required this.bookId,
    required this.language,
    required this.engineId,
    required this.count,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineName = _engineDisplayName(engineId);

    return Dismissible(
      key: ValueKey('$bookId-$language-$engineId'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDeleteEngine(context, ref),
      onDismissed: (_) => _performDeleteEngine(ref, context, bookId, language, engineId, count),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(engineName, style: const TextStyle(fontSize: 14)),
          ),
          Text('$count 条', style: TextStyle(
              fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ]),
      ),
    );
  }

  String _engineDisplayName(String id) {
    if (id == 'local_bergamot') return 'Bergamot 本地引擎';
    if (id == 'openai') return 'OpenAI';
    if (id == 'custom_api') return '自定义 API';
    return id;
  }

  Future<bool?> _confirmDeleteEngine(BuildContext context, WidgetRef ref) async {
    final langName = languageNames[language] ?? language;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除引擎译文'),
        content: Text('确定删除「$langName」中「${_engineDisplayName(engineId)}」的 $count 条译文吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              // 在 dismiss 确认后立刻执行删除
              Navigator.pop(ctx, true);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 引擎删除的实际逻辑（由 Dismissible 确认后调用）
Future<void> _performDeleteEngine(
    WidgetRef ref, BuildContext context,
    String bookId, String language, String engineId, int count) async {
  final libraryPath = ref.read(libraryPathProvider);
  final fm = TranslationFileManager(p.join(libraryPath, 'books', bookId), bookId: bookId);
  await fm.deleteEngineFromLanguage(language, engineId);

  // 检查是否整个语言版本已没内容了
  final remaining = await fm.listEnginesForLanguage(language);
  final db = LibraryDatabase();
  if (remaining.isEmpty) {
    await fm.deleteTranslation(language);
    await db.deleteTranslationStatus(bookId, language);
  } else {
    final sentenceCount = await fm.translationSentenceCount(language);
    final engines = await fm.listEnginesForLanguage(language);
    final engineIds = engines.map((e) => e.engineId).toSet();
    final book = await db.getBook(bookId);
    await db.saveTranslationStatus(
      bookId: bookId,
      bookTitle: book?.title ?? '',
      language: language,
      sentenceCount: sentenceCount,
      engineId: engineIds.join(','),
      status: 'completed',
    );
  }
  ref.invalidate(bookTranslationDetailProvider(bookId));
  ref.invalidate(scannedTranslationsProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已删除「${_engineDisplayName(engineId)}」译文'),
      behavior: SnackBarBehavior.floating,
    ));
  }
  if (!context.mounted) return;
  await _popIfNoTranslationsLeft(ref, context, bookId);
}

/// 若该书已无任何译文，回退到翻译管理界面
Future<void> _popIfNoTranslationsLeft(
    WidgetRef ref, BuildContext context, String bookId) async {
  final libraryPath = ref.read(libraryPathProvider);
  final fm = TranslationFileManager(p.join(libraryPath, 'books', bookId), bookId: bookId);
  final langs = await fm.listAvailableLanguages();
  if (langs.isEmpty && context.mounted) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/translation-management');
    }
  }
}

/// 语言版本删除的实际逻辑（由 Dismissible 确认后调用）
Future<void> _performDeleteLanguage(
    WidgetRef ref, BuildContext context,
    String bookId, String language) async {
  final langName = languageNames[language] ?? language;
  final libraryPath = ref.read(libraryPathProvider);
  final fm = TranslationFileManager(p.join(libraryPath, 'books', bookId), bookId: bookId);
  await fm.deleteTranslation(language);
  final db = LibraryDatabase();
  await db.deleteTranslationStatus(bookId, language);
  ref.invalidate(bookTranslationDetailProvider(bookId));
  ref.invalidate(scannedTranslationsProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已删除「$langName」译文'),
      behavior: SnackBarBehavior.floating,
    ));
  }
  if (!context.mounted) return;
  await _popIfNoTranslationsLeft(ref, context, bookId);
}

String _engineDisplayName(String id) {
  if (id == 'local_bergamot') return 'Bergamot 本地引擎';
  if (id == 'openai') return 'OpenAI';
  if (id == 'custom_api') return '自定义 API';
  return id;
}