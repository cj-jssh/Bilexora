import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/utils/utils.dart';
import '../../core/database/library_database.dart';
import '../../core/storage/book_package_manager.dart';
import '../../core/storage/book_importer.dart';
import '../../core/storage/translation_file.dart';
import '../../core/models/models.dart';
import '../settings/settings_screen.dart';
import '../settings/translation_engine_screen.dart';
import '../translation/local_translation_service.dart';
import '../translation/bergamot_flow.dart';
import '../../core/state/app_state.dart';
import '../translation/translation_task_manager.dart';

final libraryDbProvider = Provider<LibraryDatabase>((ref) => LibraryDatabase());

final libraryPathProvider = Provider<String>((ref) {
  throw UnimplementedError('libraryPathProvider must be overridden in main.dart');
});

final bookPackageManagerProvider = Provider<BookPackageManager>((ref) {
  return BookPackageManager(ref.watch(libraryPathProvider));
});

final libraryBooksProvider = FutureProvider<List<Book>>((ref) async {
  return ref.watch(libraryDbProvider).getAllBooks();
});

final recentBooksProvider = FutureProvider<List<({Book book, ReadingProgress? progress})>>((ref) async {
  final db = LibraryDatabase();
  final books = await db.getRecentBooks(limit: 3);
  final result = <({Book book, ReadingProgress? progress})>[];
  for (final book in books) {
    result.add((book: book, progress: await db.getProgress(book.id)));
  }
  return result;
});

final readingProgressProvider = FutureProvider.family<ReadingProgress?, String>((ref, bookId) {
  return LibraryDatabase().getProgress(bookId);
});

final bookFinishedProvider = FutureProvider.family<bool, String>((ref, bookId) async {
  final v = await LibraryDatabase().getSetting('book_finished_$bookId');
  return v == '1';
});

enum LibraryViewMode { grid, list }
enum LibrarySortMode { recent, title, author, manual }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibraryViewMode _viewMode = LibraryViewMode.list;
  LibrarySortMode _sortMode = LibrarySortMode.recent;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = LibraryDatabase();
    final viewMode = await db.getSetting('library_view_mode');
    if (viewMode == 'grid') { setState(() => _viewMode = LibraryViewMode.grid); }
    final sortMode = await db.getSetting('library_sort_mode');
    if (sortMode == 'title') { setState(() => _sortMode = LibrarySortMode.title); }
    else if (sortMode == 'author') { setState(() => _sortMode = LibrarySortMode.author); }
    else if (sortMode == 'manual') { setState(() => _sortMode = LibrarySortMode.manual); }
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(libraryBooksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书库'),
        actions: [
          IconButton(icon: const Icon(Icons.bookmark_outline), tooltip: '生词本', onPressed: () => context.push('/vocabulary')),
          _buildMoreMenu(),
        ],
      ),
      body: booksAsync.when(
        data: (books) {
          if (books.isEmpty) { return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.library_books, size: 64, color: Colors.grey),
            SizedBox(height: 16), Text('书库为空', style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8), Text('点击 ⋮ 菜单导入书籍', style: TextStyle(color: Colors.grey)),
          ])); }
          final sorted = _sortedBooks(books);
          return _viewMode == LibraryViewMode.grid ? _buildGridView(sorted) : _buildListView(sorted);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildMoreMenu() {
    final primary = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert), tooltip: '更多',
      onSelected: (v) {
        switch (v) {
          case 'import_local': _importLocalBook();
          case 'translation_mgmt': context.push('/translation-management');
          case 'view_grid': setState(() => _viewMode = LibraryViewMode.grid); _saveViewMode();
          case 'view_list': setState(() => _viewMode = LibraryViewMode.list); _saveViewMode();
          case 'sort_recent': setState(() => _sortMode = LibrarySortMode.recent); _saveSortMode();
          case 'sort_title': setState(() => _sortMode = LibrarySortMode.title); _saveSortMode();
          case 'sort_author': setState(() => _sortMode = LibrarySortMode.author); _saveSortMode();
          case 'sort_manual': setState(() => _sortMode = LibrarySortMode.manual); _saveSortMode();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(enabled: false, height: 32, child: Text('导入本地书籍', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary))),
        PopupMenuItem(value: 'import_local', child: Row(children: [Icon(Icons.download_rounded, size: 20, color: primary), const SizedBox(width: 12), const Text('本地导入', style: TextStyle(fontSize: 15))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'translation_mgmt', child: Row(children: [Icon(Icons.translate, size: 20, color: primary), const SizedBox(width: 12), const Text('翻译管理', style: TextStyle(fontSize: 15))])),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, height: 32, child: Text('显示方式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary))),
        _viewItem(Icons.grid_view_rounded, '网格', LibraryViewMode.grid, primary),
        _viewItem(Icons.list_alt_rounded, '列表', LibraryViewMode.list, primary),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, height: 32, child: Text('排序方式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary))),
        _sortItem(Icons.schedule_rounded, '最近阅读', LibrarySortMode.recent, primary),
        _sortItem(Icons.menu_book_rounded, '书名', LibrarySortMode.title, primary),
        _sortItem(Icons.person_rounded, '作者', LibrarySortMode.author, primary),
        _sortItem(Icons.drag_handle_rounded, '手动', LibrarySortMode.manual, primary),
      ],
    );
  }

  PopupMenuItem<String> _viewItem(IconData icon, String label, LibraryViewMode mode, Color primary) {
    final sel = _viewMode == mode;
    return PopupMenuItem(value: 'view_${mode.name}', child: Row(children: [
      Icon(icon, size: 20, color: sel ? primary : null),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(fontSize: 15, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
      const Spacer(), if (sel) Icon(Icons.check, size: 18, color: primary),
    ]));
  }

  PopupMenuItem<String> _sortItem(IconData icon, String label, LibrarySortMode mode, Color primary) {
    final sel = _sortMode == mode;
    return PopupMenuItem(value: 'sort_${mode.name}', child: Row(children: [
      Icon(icon, size: 20, color: sel ? primary : null),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(fontSize: 15, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
      const Spacer(), if (sel) Icon(Icons.check, size: 18, color: primary),
    ]));
  }

  Future<void> _saveViewMode() async {
    final db = LibraryDatabase();
    await db.setSetting('library_view_mode', _viewMode.name);
  }

  Future<void> _saveSortMode() async {
    final db = LibraryDatabase();
    await db.setSetting('library_sort_mode', _sortMode.name);
  }

  List<Book> _sortedBooks(List<Book> books) {
    final sorted = List<Book>.from(books);
    switch (_sortMode) {
      case LibrarySortMode.recent:
        sorted.sort((a, b) => (b.lastReadAt ?? b.addedAt ?? DateTime(0)).compareTo(a.lastReadAt ?? a.addedAt ?? DateTime(0)));
      case LibrarySortMode.title: sorted.sort((a, b) => a.title.compareTo(b.title));
      case LibrarySortMode.author: sorted.sort((a, b) => a.author.compareTo(b.author));
      case LibrarySortMode.manual: break;
    }
    return sorted;
  }

  Future<void> _deleteBook(Book book) async {
    final libraryPath = ref.read(libraryPathProvider);
    final pkg = BookPackageManager(libraryPath);
    final db = ref.read(libraryDbProvider);
    try {
      await db.deleteBook(book.id);
      await pkg.deleteBookPackage(book.id);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(recentBooksProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除「${book.title}」'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      debugPrint('删除失败: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  Future<bool> _confirmDeleteBook(Book book) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要删除「${book.title}」吗？\n此操作不可撤销，所有阅读进度和翻译数据将被清除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _markBookFinished(Book book) async {
    final db = LibraryDatabase();
    await db.setSetting('book_finished_${book.id}', '1');
    ref.invalidate(bookFinishedProvider(book.id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将「${book.title}」标记为已读完'), behavior: SnackBarBehavior.floating)); }
  }

  void _showBookMenu(BuildContext context, Book book) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); _startBatchTranslate(book); },
            child: const Row(children: [Icon(Icons.translate), SizedBox(width: 12), Text('翻译全本')]),
          ),
          SimpleDialogOption(
            onPressed: () { Navigator.pop(ctx); _confirmDeleteBook(book).then((c) { if (c) _deleteBook(book); }); },
            child: Row(children: [
              Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<Book> books) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.75),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return _GridBookCard(
            key: ValueKey(book.id),
            book: book,
            onTranslate: () => _startBatchTranslate(book),
            onDelete: () => _confirmDeleteBook(book).then((c) { if (c) _deleteBook(book); }),
            onMarkFinished: () => _markBookFinished(book),
          );
        },
      ),
    );
  }

  Widget _buildListView(List<Book> books) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: books.length,
      itemBuilder: (context, index) => _ListBookCard(key: ValueKey(books[index].id), book: books[index], onMenu: () => _showBookMenu(context, books[index])),
    );
  }

  Future<void> _importLocalBook() async {
    try {
      if (!mounted) { return; }
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['epub', 'txt']);
      if (result.isEmpty) { return; }
      final filePath = result.first.path;
      if (filePath == null) { return; }
      final dir = await getApplicationDocumentsDirectory();
      final libraryPath = p.join(dir.path, 'library');
      final pkg = BookPackageManager(libraryPath);
      final importer = BookImporter(pkg);
      if (!mounted) { return; }
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      final ext = p.extension(filePath).toLowerCase();
      final book = ext == '.epub' ? await importer.importEpub(filePath) : await importer.importTxt(filePath);
      final finalBook = book.copyWith(addedAt: DateTime.now(), updatedAt: DateTime.now());
      await ref.read(libraryDbProvider).upsertBook(finalBook);
      ref.invalidate(libraryBooksProvider);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        final translateOnImport = ref.read(translateOnImportProvider);
        if (translateOnImport) {
          _showImportTranslatePrompt(finalBook);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入「${book.title}」'), behavior: SnackBarBehavior.floating));
        }
      }
    } catch (e, stack) {
      debugPrint('导入失败: $e\n$stack');
      if (mounted) {
        try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  void _showImportTranslatePrompt(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('已导入「${book.title}」', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('是否开始翻译？'),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后手动')),
              const SizedBox(width: 12),
              FilledButton(onPressed: () { Navigator.pop(ctx); _startBatchTranslate(book); }, child: const Text('开始翻译')),
            ]),
          ]),
        ),
      ),
    );
  }

  void _startBatchTranslate(Book book) {
    _doBatchTranslate(book);
  }

  Future<void> _doBatchTranslate(Book book) async {
    ref.read(translationProgressProvider(book.id).notifier).state = 0.0;
    final libraryPath = ref.read(libraryPathProvider);
    final pkg = BookPackageManager(libraryPath);

    final reader = await pkg.openContentDat(book.id);
    if (reader == null) {
      ref.read(translationProgressProvider(book.id).notifier).state = null;
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取书籍内容'), behavior: SnackBarBehavior.floating)); }
      return;
    }

    final allSentences = <({int globalIndex, String text})>{};
    for (int i = 0; i < reader.chapterCount; i++) {
      final ch = reader.readChapter(i);
      if (ch == null) { continue; }
      for (final block in ch.blocks) {
        block.when(
          paragraph: (p) { for (final s in p.sentences) { allSentences.add((globalIndex: s.charOffset, text: s.text)); } },
          image: (_, _) {},
        );
      }
    }

    if (allSentences.isEmpty) {
      ref.read(translationProgressProvider(book.id).notifier).state = null;
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书中没有可翻译的内容'), behavior: SnackBarBehavior.floating)); }
      return;
    }

    final engines = ref.read(translationEnginesProvider);
    final active = engines.isNotEmpty ? engines.first : null;
    if (active == null) {
      ref.read(translationProgressProvider(book.id).notifier).state = null;
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未设置翻译引擎'), behavior: SnackBarBehavior.floating)); }
      return;
    }

    if (!mounted) { return; }

    final learningLang = ref.read(bilingualLearningLanguageProvider);
    final bookLang = book.language.isNotEmpty ? book.language : 'en';
    final fm = TranslationFileManager(p.join(libraryPath, 'books', book.id), bookId: book.id);
    final priority = engines.indexOf(active);

    // 注册翻译任务
    final nativeLang = ref.read(nativeLanguageProvider);
    final (srcLang, tgtLang) = resolveLocalDirection(
      bookLanguage: bookLang,
      nativeLanguage: nativeLang,
      learningLanguage: learningLang,
    );
    ref.read(translationTaskManagerProvider.notifier).addTask(TranslationTask(
      bookId: book.id,
      bookTitle: book.title,
      totalSentences: allSentences.length,
    ));
    // 清除可能遗留的取消标记
    LocalTranslationService.clearCancel(book.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在翻译 ${allSentences.length} 句...'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
    // 开始通知（结束通知在完成/失败/取消时发送，形成有头有尾的提示）
    LibraryDatabase().addNotification(
      type: 'translation_started',
      title: '开始翻译',
      body: '「${book.title}」开始翻译 ${allSentences.length} 句',
      bookId: book.id,
    );

    try {
      if (active.id == 'local_bergamot') {
        final svc = LocalTranslationService(bookId: book.id, libraryPath: libraryPath);
        final allList = allSentences.toList();
        final results = <int, String>{};

        // 监听 progress，用 1% 阈值 + 3s 兜底防频繁 UI 重建
        double lastReported = -1.0;
        DateTime lastUpdateTime = DateTime.now();
        void progressListener() {
          final v = svc.progress.value;
          final now = DateTime.now();
          if ((v - lastReported).abs() >= 0.01 ||
              now.difference(lastUpdateTime).inSeconds >= 3) {
            ref.read(translationProgressProvider(book.id).notifier).state = v;
            lastReported = v;
            lastUpdateTime = now;
          }
        }
        svc.progress.addListener(progressListener);

        // 在翻译前创建 writer，传入 translate 方法实现中间落盘
        final writer = BatchFileWriter(fm, tgtLang, active.id, priority, totalCount: allList.length);

        if (srcLang == 'en' || tgtLang == 'en') {
          final nonEnglishLang = srcLang == 'en' ? tgtLang : srcLang;
          if (!await ensureBergamotModel(context, ref, nonEnglishLang)) {
            svc.progress.removeListener(progressListener);
            return;
          }

          final r = await svc.translateParagraph(
            sentences: allList,
            sourceLanguage: srcLang, targetLanguage: tgtLang,
            // 覆盖模式：重译所有句子，修复旧版本引擎错配产生的乱码译文
            overwriteExisting: true,
            writer: writer,
          );
          results.addAll(r);
        } else {
          if (!mounted) return;
          final srcOk = await ensureBergamotModel(context, ref, srcLang);
          if (!srcOk) {
            svc.progress.removeListener(progressListener);
            return;
          }
          if (!mounted) return;
          final tgtOk = await ensureBergamotModel(context, ref, tgtLang);
          if (!tgtOk) {
            svc.progress.removeListener(progressListener);
            return;
          }

          final r = await svc.translateWithRelay(
            sentences: allList,
            sourceLanguage: srcLang, targetLanguage: tgtLang,
            overwriteExisting: true,
            writer: writer,
          );
          results.addAll(r);
        }
        svc.progress.removeListener(progressListener);
        ref.read(translationProgressProvider(book.id).notifier).state = 1.0;
        // writer.flush() 已在 translate 方法内部调用
        // 只有未被取消才标记完成
        if (!LocalTranslationService.isBookCancelled(book.id)) {
          ref.read(translationTaskManagerProvider.notifier).markCompleted(book.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('翻译完成: ${results.length} 句'), behavior: SnackBarBehavior.floating));
            final db = LibraryDatabase();
            await db.saveTranslationStatus(bookId: book.id, bookTitle: book.title, language: tgtLang, sentenceCount: results.length, engineId: active.id);
            await db.addNotification(type: 'translation', title: '翻译完成', body: '「${book.title}」已翻译 ${results.length} 句', bookId: book.id);
          }
        } else {
          // 已取消：已完成部分已写入 content_{lang}.dat，同样持久化翻译状态，
          // 否则翻译管理页看不到这部分已完成译文
          LocalTranslationService.clearCancel(book.id);
          ref.read(translationProgressProvider(book.id).notifier).state = null;
          if (results.isNotEmpty) {
            final db = LibraryDatabase();
            await db.saveTranslationStatus(
              bookId: book.id,
              bookTitle: book.title,
              language: tgtLang,
              sentenceCount: results.length,
              engineId: active.id,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已取消，已完成 ${results.length} 句译文已保存'), behavior: SnackBarBehavior.floating));
            }
          }
        }
      } else {
        final translated = await translateWithAI(
          engine: active, sentences: allSentences.toList(),
          sourceLanguage: bookLang, targetLanguage: learningLang,
          onProgress: (processed, total) {
            ref.read(translationProgressProvider(book.id).notifier).state = processed / total;
          },
        );
        ref.read(translationProgressProvider(book.id).notifier).state = 1.0;
        if (translated.isNotEmpty) {
          await fm.appendTranslation(lang: learningLang, engineId: active.id, priority: priority, results: translated);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('翻译完成: ${translated.length} 句'), behavior: SnackBarBehavior.floating));
          final db = LibraryDatabase();
          await db.saveTranslationStatus(bookId: book.id, bookTitle: book.title, language: learningLang, sentenceCount: translated.length, engineId: active.id);
          await db.addNotification(type: 'translation', title: '翻译完成', body: '「${book.title}」已翻译 ${translated.length} 句', bookId: book.id);
        }
      }
      ref.read(translationProgressProvider(book.id).notifier).state = null;
    } catch (e) {
      ref.read(translationProgressProvider(book.id).notifier).state = null;
      ref.read(translationTaskManagerProvider.notifier).markFailed(book.id, translateErrorMessage(e));
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('翻译失败: ${translateErrorMessage(e)}'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4))); }
    }
  }





}


// ── 列表卡片 ────────────────────────────────

class _ListBookCard extends ConsumerWidget {
  final Book book;
  final VoidCallback? onMenu;
  const _ListBookCard({super.key, required this.book, this.onMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryPath = ref.watch(libraryPathProvider);
    return GestureDetector(
      onLongPress: () => onMenu?.call(),
      child: Card(
        child: ListTile(
          leading: Container(width: 48, height: 64,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
            child: _buildCover(libraryPath)),
          title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(book.author.isNotEmpty ? book.author : '未知作者', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/reader/${book.id}'),
        ),
      ),
    );
  }

  Widget _buildCover(String libraryPath) {
    final coverPath = book.cover != null ? p.join(libraryPath, 'books', book.id, 'images', book.cover!) : null;
    if (coverPath != null && File(coverPath).existsSync()) {
      return ClipRRect(borderRadius: BorderRadius.circular(4),
          child: Image.file(File(coverPath), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.book, size: 32)));
    }
    return const Icon(Icons.book, size: 32);
  }
}

// ── 网格卡片 ────────────────────────────────

final class _GridBookCard extends ConsumerWidget {
  final Book book;
  final VoidCallback? onTranslate;
  final VoidCallback? onDelete;
  final VoidCallback? onMarkFinished;
  const _GridBookCard({
    super.key,
    required this.book,
    this.onTranslate,
    this.onDelete,
    this.onMarkFinished,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryPath = ref.watch(libraryPathProvider);
    final finishedAsync = ref.watch(bookFinishedProvider(book.id));
    final progressAsync = ref.watch(readingProgressProvider(book.id));
    final translationProgress = ref.watch(translationProgressProvider(book.id));
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => context.push('/reader/${book.id}'),
      child: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cover image
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCover(libraryPath),
                    // Finished badge on cover
                    if (finishedAsync.valueOrNull == true && translationProgress == null)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 2),
                            Text('已读完', style: TextStyle(fontSize: 10, color: Colors.white)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Bottom section: progress + 3-dot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  // Reading progress or translation progress
                  if (translationProgress != null)
                    Text(
                      '${(translationProgress * 100).round()}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary),
                    )
                  else
                    Text(
                      progressAsync.valueOrNull != null
                          ? '${(progressAsync.valueOrNull!.percentage * 100).round()}%'
                          : '0%',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  const Spacer(),
                  // Translation progress bar
                  if (translationProgress != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 48, height: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1.5),
                          child: LinearProgressIndicator(
                            value: translationProgress.clamp(0.0, 1.0),
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                  // Horizontal 3-dot button
                  PopupMenuButton<int>(
                    onSelected: (value) {
                      if (value == 0) { onTranslate?.call(); }
                      else if (value == 1) { onMarkFinished?.call(); }
                      else if (value == 2) { onDelete?.call(); }
                    },
                    offset: const Offset(-140, 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    color: Colors.white.withValues(alpha: 0.9),
                    child: translationProgress != null
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              value: translationProgress.clamp(0.0, 1.0),
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.more_horiz, size: 20),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.translate, size: 16),
                          ),
                          const SizedBox(width: 12),
                          const Text('翻译全本'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 1,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.check_circle_outline, size: 16),
                          ),
                          const SizedBox(width: 12),
                          const Text('标记为已读完'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                            child: Icon(Icons.delete_outline, size: 16, color: Theme.of(context).colorScheme.error),
                          ),
                          const SizedBox(width: 12),
                          Text('移除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(String libraryPath) {
    final coverPath = book.cover != null ? p.join(libraryPath, 'books', book.id, 'images', book.cover!) : null;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(File(coverPath), fit: BoxFit.cover, width: double.infinity, height: double.infinity,
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.book, size: 48, color: Colors.grey)));
    }
    return const Center(child: Icon(Icons.book, size: 48, color: Colors.grey));
  }
}