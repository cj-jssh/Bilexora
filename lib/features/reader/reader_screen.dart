import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/models/models.dart';
import '../../core/storage/book_package_manager.dart';
import '../../core/storage/content_dat_reader.dart';
import '../../core/database/library_database.dart';
import '../../core/utils/utils.dart';
import '../library/library_screen.dart';
import '../home/home_screen.dart';
import '../settings/settings_screen.dart';
import '../translation/local_translation_service.dart';
import '../translation/bergamot_flow.dart';
import '../../core/storage/translation_file.dart';
import 'widgets/word_lookup_popup.dart';

import '../settings/translation_engine_screen.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final String bookId;
  const ReaderScreen({super.key, required this.bookId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

/// 章节加载方向：replace = 替换全部（章节跳转），
/// append = 追加到末尾（向下滚动到底部），
/// prepend = 插入到开头（向上滚动到顶部）
enum LoadDirection { replace, append, prepend }

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ContentDatReader? _reader;
  Book? _bookMeta;
  Chapter? _currentChapter;
  int _currentChapterIndex = 0;
  int _chapterCount = 0;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  Timer? _saveTimer;
  bool _showControls = false;
  bool _showMenuPanel = false;
  Timer? _controlHideTimer;

  int _currentVisibleParagraphIndex = 0;

  // 连续阅读：累积所有已加载章节的块
  final List<ContentBlock> _allBlocks = [];
  int _loadedDownToChapter = -1; // 已加载的最小章节索引（向上滑动时减少）
  int _loadedUpToChapter = -1;   // 已加载的最大章节索引（向下滑动时增加）

  // 预加载章节数量（可配置，默认 5）
  int _preloadCount = 5;

  // 章节解码缓存：后台/空闲时预解码, 滚动到边缘时命中缓存则零解码,
  // 避免在滚动瞬间同步阻塞主 isolate 解码整章造成卡顿。
  final Map<int, Chapter> _chapterCache = {};
  final List<int> _prefetchQueue = []; // 待解码章节队列(先靠近先解)
  bool _prefetchActive = false;
  Timer? _prefetchTimer;

  // 加载方向锁，防止重复触发
  bool _isAppending = false;
  bool _isPrepending = false;
  DateTime _lastAppendTime = DateTime(2000);
  DateTime _lastPrependTime = DateTime(2000);

  // 翻译数据：sentence globalIndex → 译文
  final Map<int, String> _translationMap = {};
  String _bookLanguage = 'en';
  // 已加载译文的语言（避免每次追加章节都全量重读翻译文件，造成滚动卡顿）
  final Set<String> _translationLoadedLangs = {};
  // content.dat 每章真实句数（惰性计算一次并缓存，避免滚动时反复解析全书）
  Future<List<int>>? _perChCountsFuture;

  // 点击展示模式（句子级：key = sentence.charOffset）
  final Set<int> _revealedSentences = {};
  final Set<int> _noTranslationSentences = {};

  // ── 分区渲染: 扁平句子条目 + 高度缓存 ──────────────────────
  // 每个逻辑行(item)的已测高度缓存, 惰性填充, 供提前预计算与滚动定位。
  // 条目类型: separator / sentence(原文) / translation(译文)
  final List<double> _itemHeightCache = [];
  // 译文行译 GlobalKey (用于展开/折叠时锚点滚动补偿)
  final Map<int, GlobalKey> _translationKeys = {};


  // 阅读计时
  DateTime? _sessionStart;
  Timer? _readingTimer;

  double _fontSize = 20.0;
  double _lineHeight = 1.9;
  double _letterSpacing = 1.55;
  Color _textColor = Colors.black87;
  Color _bgColor = Colors.white;

  // 当前高亮的单词和其所在文本行的全文（用于高亮显示）
  String? _highlightedWord;
  String? _highlightedText;
  int? _highlightWordStart;
  int? _highlightWordEnd;

  @override
  void initState() {
    super.initState();
    _loadReaderSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBook());
    _scrollController.addListener(_onScroll);
    _startReadingTimer();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _saveTimer?.cancel();
    _controlHideTimer?.cancel();
    _readingTimer?.cancel();
    _prefetchTimer?.cancel();
    _saveReadingTime();
    _saveReaderSettings();
    try { _invalidateHomeProviders(); } catch (_) {}
    super.dispose();
  }

  void _loadReaderSettings() {
    final db = LibraryDatabase();
    db.getSetting('reader_fontSize').then((v) {
      if (v != null && mounted) setState(() => _fontSize = double.tryParse(v) ?? 20.0);
    });
    db.getSetting('reader_lineHeight').then((v) {
      if (v != null && mounted) setState(() => _lineHeight = double.tryParse(v) ?? 1.9);
    });
    db.getSetting('reader_letterSpacing').then((v) {
      if (v != null && mounted) setState(() => _letterSpacing = double.tryParse(v) ?? 1.55);
    });
    db.getSetting('reader_theme').then((v) {
      if (v != null && mounted) {
        setState(() {
          switch (v) {
            case 'light': _textColor = Colors.black87; _bgColor = Colors.white;
            case 'warm': _textColor = Colors.brown[800]!; _bgColor = const Color(0xFFFFF8E1);
            case 'dark': _textColor = Colors.white70; _bgColor = const Color(0xFF1E1E1E);
          }
        });
      }
    });
    // 从 DB 加载双语设置并同步到 provider，确保阅读器启动时设置生效
    db.getSetting('bilingual_enabled').then((v) {
      if (v != null && mounted) {
        ref.read(bilingualEnabledProvider.notifier).state = v == '1';
      }
    });
    db.getSetting('bilingual_layout').then((v) {
      if (v != null && mounted) {
        ref.read(bilingualLayoutProvider.notifier).state = v;
      }
    });
    db.getSetting('bilingual_show_mode').then((v) {
      if (v != null && mounted) {
        ref.read(bilingualShowModeProvider.notifier).state = v;
      }
    });
    db.getSetting('bilingual_learning').then((v) {
      if (v != null && mounted) {
        ref.read(bilingualLearningLanguageProvider.notifier).state = v;
      }
    });
    db.getSetting('native_language').then((v) {
      if (v != null && mounted) {
        ref.read(nativeLanguageProvider.notifier).state = v;
      }
    });
    db.getSetting('reader_preloadCount').then((v) {
      if (v != null && mounted) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed >= 1 && parsed <= 20) {
          setState(() => _preloadCount = parsed);
        }
      }
    });
  }

  void _saveReaderSettings() {
    final db = LibraryDatabase();
    db.setSetting('reader_fontSize', _fontSize.toString());
    db.setSetting('reader_lineHeight', _lineHeight.toString());
    db.setSetting('reader_letterSpacing', _letterSpacing.toString());
    String theme;
    if (_bgColor == Colors.white) { theme = 'light'; }
    else if (_bgColor == const Color(0xFFFFF8E1)) { theme = 'warm'; }
    else { theme = 'dark'; }
    db.setSetting('reader_theme', theme);
    db.setSetting('reader_preloadCount', _preloadCount.toString());
  }

  void _toggleControls({bool showMenuDirectly = false}) {
    if (_showControls) {
      setState(() { _showControls = false; _showMenuPanel = false; });
      _controlHideTimer?.cancel();
    } else {
      setState(() {
        _showControls = true;
        if (showMenuDirectly) _showMenuPanel = true;
      });
      _controlHideTimer?.cancel();
      _controlHideTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() { _showControls = false; _showMenuPanel = false; });
      });
    }
  }

  Future<void> _loadBook() async {
    try {
      final libraryPath = ref.read(libraryPathProvider);
      final packageManager = BookPackageManager(libraryPath);
      final meta = await packageManager.readBookMeta(widget.bookId);
      final reader = await packageManager.openContentDat(widget.bookId);
      if (!mounted) return;
      if (reader == null) {
        setState(() { _error = '无法打开书籍数据'; _isLoading = false; });
        return;
      }
      setState(() {
        _reader = reader;
        _bookMeta = meta;
        _bookLanguage = meta?.language.isNotEmpty == true ? meta!.language : 'en';
        _chapterCount = reader.chapterCount;
        _isLoading = false;
      });
      await _restoreProgress();
      if (_currentChapter == null) _loadChapter(0);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '加载书籍失败: $e'; _isLoading = false; });
    }
  }

  Future<void> _restoreProgress() async {
    try {
      final db = LibraryDatabase();
      final progress = await db.getProgress(widget.bookId);
      if (!mounted || progress == null) return;
      if (progress.chapter < _chapterCount) {
        _loadChapter(progress.chapter, savedParagraph: progress.paragraph);
      }
    } catch (e) { debugPrint('恢复阅读进度失败: $e'); }
  }

  /// 加载章节，支持三种方向：
  /// - [LoadDirection.replace]：替换全部内容（章节跳转、首次加载）
  /// - [LoadDirection.append]：追加到末尾（向下滚动到底部）
  /// - [LoadDirection.prepend]：插入到开头（向上滚动到顶部）
  void _loadChapter(int index,
      {int? savedParagraph, LoadDirection direction = LoadDirection.replace}) {
    final reader = _reader;
    if (reader == null) {
      _releaseLock(direction);
      return;
    }

    // 在 clamp 之前先做边界检查，避免负索引被 clamp 到 0 后与已有章节冲突
    if (direction == LoadDirection.prepend && (index < 0 || index >= _loadedDownToChapter)) {
      _releaseLock(direction);
      return;
    }
    if (direction == LoadDirection.append && (index >= _chapterCount || index <= _loadedUpToChapter)) {
      _releaseLock(direction);
      return;
    }

    final clamped = index.clamp(0, _chapterCount - 1);

    // 优先从预取缓存取章(零解码), 未命中才同步解码
    var chapter = _chapterCache.remove(clamped);
    chapter ??= reader.readChapter(clamped);
    if (chapter == null) {
      _releaseLock(direction);
      return;
    }

    // 当前章节变动后, 后台预解码四周章节, 供后续滚动直接命中缓存
    _prefetchChapters(clamped);

    // 保存 prepend 前的滚动位置，用于 setState 后补偿
    final prePrependScrollOffset = direction == LoadDirection.prepend && _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final prePrependMaxScroll = direction == LoadDirection.prepend && _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    if (direction == LoadDirection.replace) {
      _allBlocks
        ..clear()
        ..addAll(chapter.blocks);
      _loadedDownToChapter = clamped;
      _loadedUpToChapter = clamped;
    } else if (direction == LoadDirection.prepend) {
      _allBlocks.insertAll(0, chapter.blocks);
      _loadedDownToChapter = clamped;
    } else {
      // append
      _allBlocks.addAll(chapter.blocks);
      _loadedUpToChapter = clamped;
    }

    // 加载翻译：增量合并，不覆盖已有数据
    _loadTranslations();

    setState(() {
      _currentChapter = chapter;
      _currentChapterIndex = clamped;
    });

    // 滚动位置补偿：prepend 后内容从顶部插入，需要增加偏移量
    // 使用 post-frame 回调确保新布局已完成
    if (direction == LoadDirection.prepend) {
      final oldMax = prePrependMaxScroll;
      final oldOffset = prePrependScrollOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients || !mounted) return;
        final newMax = _scrollController.position.maxScrollExtent;
        final delta = newMax - oldMax;
        _scrollController.jumpTo((oldOffset + delta).clamp(0.0, newMax));
        _isPrepending = false;
      });
    } else if (direction == LoadDirection.append) {
      // append 后保持滚动位置不变（新内容在下方），下一帧释放锁
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _isAppending = false;
      });
    } else if (direction == LoadDirection.replace) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      if (savedParagraph != null && savedParagraph > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToParagraph(savedParagraph));
      }
    }

    _updateLastReadAt().then((_) { if (mounted) _invalidateHomeProviders(); });
  }

  /// 预解码 [centerIndex] 四周的章节到缓存。解码是同步 CPU 操作,
  /// 逐章放到定时器回调里分段执行, 让每帧之间有间隔, 避免一次性阻塞主线程。
  /// 已缓存/正在排程的章节跳过, 保证不重复。
  void _prefetchChapters(int centerIndex) {
    final reader = _reader;
    if (reader == null) return;

    // 由近及远收集待解章节
    final targets = <int>[];
    for (int i = 1; i <= _preloadCount; i++) {
      final next = centerIndex + i;
      final prev = centerIndex - i;
      if (next < _chapterCount && !_chapterCache.containsKey(next)) {
        targets.add(next);
      }
      if (prev >= 0 && !_chapterCache.containsKey(prev)) {
        targets.add(prev);
      }
    }
    if (targets.isEmpty) return;

    _prefetchQueue.addAll(targets);
    _schedulePrefetch();
  }

  void _schedulePrefetch() {
    if (_prefetchActive || _prefetchQueue.isEmpty) return;
    _prefetchActive = true;
    _prefetchTimer?.cancel();
    // 分段执行: 每帧只解一章, 其余等下一帧, 避免长任务卡住滚动
    _prefetchTimer = Timer(const Duration(milliseconds: 16), () {
      final reader = _reader;
      final next = _prefetchQueue.removeAt(0);
      if (reader != null && next >= 0 && next < _chapterCount) {
        if (!_chapterCache.containsKey(next)) {
          final ch = reader.readChapter(next);
          if (ch != null) _chapterCache[next] = ch;
        }
      }
      _prefetchActive = false;
      // 继续处理队列余下章节
      if (_prefetchQueue.isNotEmpty) _schedulePrefetch();
    });
  }

  /// 惰性计算 content.dat 每章句数，缓存结果避免滚动时反复解析全书
  Future<List<int>> _ensurePerChapterCounts() {
    return _perChCountsFuture ??= () async {
      final reader = _reader;
      final counts = <int>[];
      for (int i = 0; i < (reader?.chapterCount ?? 0); i++) {
        counts.add(reader?.readChapter(i)?.sentenceCount ?? 0);
      }
      return counts;
    }();
  }

  /// 加载译文。每种语言只加载一次，避免每次滚动追加章节都全量重读翻译文件。
  ///
  /// 原文语言 ≠ 母语时（本地引擎会把译文写到母语），书库「翻译全本」的结果
  /// 存在 resolveLocalDirection 得到的目标语言下；而 AI 引擎写到学习语言。
  /// 因此两个语言都尝试加载、合并映射，确保译文能显示出来。
  void _loadTranslations() {
    final reader = _reader;
    if (reader == null) return;
    final libraryPath = ref.read(libraryPathProvider);
    final fm = TranslationFileManager(
      p.join(libraryPath, 'books', widget.bookId),
      bookId: widget.bookId,
    );
    final nativeLang = ref.read(nativeLanguageProvider);
    final learningLang = ref.read(bilingualLearningLanguageProvider);
    final (_, localTarget) = resolveLocalDirection(
      bookLanguage: _bookLanguage,
      nativeLanguage: nativeLang,
      learningLanguage: learningLang,
    );
    final langs = {learningLang, localTarget};
    _ensurePerChapterCounts().then((perChCounts) async {
      for (final lang in langs) {
        if (_translationLoadedLangs.contains(lang)) continue;
        _translationLoadedLangs.add(lang);
        try {
          final extMap = await fm.loadTranslation(
              lang, perChapterSentenceCounts: perChCounts);
          if (mounted && extMap.isNotEmpty) {
            setState(() => _translationMap.addAll(extMap));
          }
        } catch (e) {
          debugPrint('[翻译] 加载[$lang]译文文件失败: $e');
        }
      }
    });
  }

  /// 安全释放方向锁，防止锁泄漏导致滚动加载永久卡死
  void _releaseLock(LoadDirection direction) {
    if (direction == LoadDirection.prepend) {
      _isPrepending = false;
    } else if (direction == LoadDirection.append) {
      _isAppending = false;
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // 对于内容很少的章节（< 600px），直接用比例判断
    const edgeThreshold = 400.0;
    const shortContentThreshold = 0.85; // 滚动超过 85% 触发下一章

    // === 向下滚动 → 加载下一章 ===
    bool shouldAppend = false;
    if (maxScroll > 0 && currentScroll >= 0) {
      if (maxScroll <= edgeThreshold) {
        // 短内容：滚动超过 85% 即触发
        shouldAppend = currentScroll / maxScroll >= shortContentThreshold;
      } else {
        // 长内容：距底 < edgeThreshold 触发
        shouldAppend = currentScroll >= maxScroll - edgeThreshold;
      }
    }
    if (shouldAppend && !_isAppending) {
      final next = _loadedUpToChapter + 1;
      final now = DateTime.now();
      if (next < _chapterCount &&
          now.difference(_lastAppendTime).inMilliseconds > 500) {
        _isAppending = true;
        _lastAppendTime = now;
        _loadChapter(next, direction: LoadDirection.append);
      }
    }

    // === 向上滚动 → 加载前一章 ===
    bool shouldPrepend = false;
    if (maxScroll > 0 && currentScroll >= 0) {
      if (maxScroll <= edgeThreshold) {
        // 短内容：滚动少于 15% 即触发
        shouldPrepend = currentScroll / maxScroll <= (1.0 - shortContentThreshold);
      } else {
        // 长内容：距顶 < edgeThreshold 触发
        shouldPrepend = currentScroll <= edgeThreshold;
      }
    }
    if (shouldPrepend && !_isPrepending) {
      final prev = _loadedDownToChapter - 1;
      final now = DateTime.now();
      if (prev >= 0 &&
          now.difference(_lastPrependTime).inMilliseconds > 500) {
        _isPrepending = true;
        _lastPrependTime = now;
        _loadChapter(prev, direction: LoadDirection.prepend);
      }
    }

    // 保存滚动进度
    if (maxScroll > 0) {
      _currentVisibleParagraphIndex = (currentScroll / maxScroll * 1000).round();
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), () => _saveProgress());
  }

  Future<void> _saveProgress() async {
    if (_currentChapter == null) return;
    try {
      final db = LibraryDatabase();
      await db.saveProgress(ReadingProgress(
        bookId: widget.bookId, chapter: _currentChapterIndex,
        paragraph: _currentVisibleParagraphIndex,
        percentage: _chapterCount > 0 ? (_currentChapterIndex + 1) / _chapterCount : 0.0,
        updatedAt: DateTime.now(),
      ));
    } catch (e) { debugPrint('保存阅读进度失败: $e'); }
  }

  void _scrollToParagraph(int paragraphIndex) {
    if (paragraphIndex <= 0 || _currentChapter == null || !_scrollController.hasClients) return;
    // 用比例近似定位
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;
    final target = maxScroll * paragraphIndex / 1000.0;
    _scrollController.jumpTo(target.clamp(0.0, maxScroll));
  }

  Future<void> _updateLastReadAt() async {
    try {
      final db = LibraryDatabase();
      final existing = await db.getBook(widget.bookId);
      if (existing != null) {
        await db.upsertBook(existing.copyWith(lastReadAt: DateTime.now(), updatedAt: DateTime.now()));
      }
    } catch (e) { debugPrint('更新阅读时间失败: $e'); }
  }

  void _invalidateHomeProviders() {
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(recentBooksProvider);
    ref.invalidate(todayReadingSecondsProvider);
    ref.invalidate(weeklySecondsProvider);
  }

  void _startReadingTimer() {
    _sessionStart = DateTime.now();
    _readingTimer?.cancel();
    _readingTimer = Timer.periodic(const Duration(seconds: 30), (_) { _saveReadingTime(); });
  }

  void _saveReadingTime() {
    if (_sessionStart == null) return;
    final elapsed = DateTime.now().difference(_sessionStart!).inSeconds;
    if (elapsed <= 0) return;
    final db = LibraryDatabase();
    db.addReadingTime(widget.bookId, elapsed);
    _sessionStart = DateTime.now();
  }

  /// 点击译文区域：切换译文的显示/隐藏（每句独立）
  void _tapTranslationArea(int sentenceGlobalIndex) {
    // 高度发生变化前, 记录锚点项(该译文行)相对视口顶部的全局Y,
    // setState 后用 Anchor 补偿滚动, 避免展开/收起时阅读位置跳动。
    double? anchorOffsetFromViewportTop;
    final key = _translationKeys[sentenceGlobalIndex];
    final anchorBox =
        key?.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox != null && anchorBox.hasSize) {
      anchorOffsetFromViewportTop =
          anchorBox.localToGlobal(Offset.zero).dy;
    }

    if (_revealedSentences.contains(sentenceGlobalIndex)) {
      // 已显示 → 隐藏
      setState(() => _revealedSentences.remove(sentenceGlobalIndex));
      _applyAnchorCorrection(sentenceGlobalIndex, anchorOffsetFromViewportTop);
      return;
    }
    // 检查是否有翻译数据
    final hasData = _translationMap[sentenceGlobalIndex]?.isNotEmpty == true;
    if (!hasData) {
      if (_noTranslationSentences.contains(sentenceGlobalIndex)) {
        // 已显示「暂无对应译文」，再次点击 → 弹出引擎选择
        _showEnginePicker(sentenceGlobalIndex);
      } else {
        // 首次点击无译文 → 显示「暂无对应译文」
        setState(() => _noTranslationSentences.add(sentenceGlobalIndex));
      }
    } else {
      setState(() => _revealedSentences.add(sentenceGlobalIndex));
      _applyAnchorCorrection(sentenceGlobalIndex, anchorOffsetFromViewportTop);
    }
  }

  /// 展开/折叠高度变化后, 把锚点行补偿回原屏幕Y位置, 防止阅读跳动。
  void _applyAnchorCorrection(int charOffset, double? anchorYBefore) {
    if (anchorYBefore == null || !mounted || !_scrollController.hasClients) {
      return;
    }
    // 隐藏时锚点行已被移除(不再有key), 改用打开前位置的 row;
    // 为稳妥, 统一用 post-frame 里对同一 charOffset 的 translation key 校正,
    // 若该行已隐藏(折叠), 则跳过(隐藏后下方上移, 行为自然)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final box = (_translationKeys[charOffset]
              ?.currentContext?.findRenderObject()) as RenderBox?;
      if (box == null || !box.hasSize) return;
      final nowY = box.localToGlobal(Offset.zero).dy;
      final delta = anchorYBefore - nowY;
      if (delta.abs() < 0.5) return;
      final pos = _scrollController.position;
      _scrollController.jumpTo(
          (pos.pixels - delta).clamp(0.0, pos.maxScrollExtent));
    });
  }

  /// 弹出翻译引擎选择对话框（默认选中第一个）
  void _showEnginePicker(int sentenceGlobalIndex) {
    final engines = ref.read(translationEnginesProvider);
    if (engines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未设置翻译引擎，请先在设置中添加'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('选择翻译引擎',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 8),
            ...List.generate(engines.length, (i) {
              final e = engines[i];
              final isDefault = i == 0;
              return ListTile(
                leading: Icon(e.iconData, color: isDefault
                    ? Theme.of(ctx).colorScheme.primary : null),
                title: Text('${e.name}${isDefault ? ' ★默认' : ''}',
                    style: TextStyle(fontWeight: isDefault ? FontWeight.w600 : FontWeight.w400)),
                subtitle: Text(e.description, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(ctx);
                  _translateSingleSentence(sentenceGlobalIndex, engine: e);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 将译文加入内存映射并按展示模式更新可见性
  void _applyTranslation(int sentenceGlobalIndex, String text) {
    setState(() {
      _translationMap[sentenceGlobalIndex] = text;
      _applyPostTranslationVisibility(sentenceGlobalIndex);
    });
  }

  /// 翻译单句（使用指定引擎），翻译后自动展示
  Future<void> _translateSingleSentence(int sentenceGlobalIndex,
      {TranslationEngine? engine}) async {
    // 从当前已加载块中找到对应句子
    String? sentenceText;
    for (final block in _allBlocks) {
      block.when(
        paragraph: (p) {
          for (final s in p.sentences) {
            if (s.charOffset == sentenceGlobalIndex) {
              sentenceText = s.text;
            }
          }
        },
        image: (_, _) {},
      );
      if (sentenceText != null) break;
    }
    if (sentenceText == null || sentenceText!.trim().isEmpty) return;
    final text = sentenceText!;

    final engines = ref.read(translationEnginesProvider);
    if (engines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未设置翻译引擎'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    final active = engine ?? engines.first;
    final learningLang = ref.read(bilingualLearningLanguageProvider);
    final libraryPath = ref.read(libraryPathProvider);
    final fm = TranslationFileManager(
      p.join(libraryPath, 'books', widget.bookId),
      bookId: widget.bookId,
    );

    try {
      setState(() {
        _noTranslationSentences.remove(sentenceGlobalIndex);
      });

      final isLocalEngine = active.id == 'local_bergamot';
      final priority = engines.indexOf(active);

      if (isLocalEngine) {
        final nativeLang = ref.read(nativeLanguageProvider);
        final (sourceLang, targetLang) = resolveLocalDirection(
          bookLanguage: _bookLanguage,
          nativeLanguage: nativeLang,
          learningLanguage: learningLang,
        );

        if (sourceLang != 'en' && targetLang != 'en') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('本地离线翻译仅支持英语与其他语言之间的翻译'), behavior: SnackBarBehavior.floating),
            );
          }
          return;
        }

        final nonEnglishLang = sourceLang == 'en' ? targetLang : sourceLang;
        if (!mounted) return;
        if (!await ensureBergamotModel(context, ref, nonEnglishLang)) return;

        final service = LocalTranslationService(bookId: widget.bookId, libraryPath: libraryPath);
        final writer = BatchFileWriter(fm, targetLang, active.id, priority, totalCount: 1);
        final results = await service.translateParagraph(
          sentences: [(globalIndex: sentenceGlobalIndex, text: text)],
          sourceLanguage: sourceLang,
          targetLanguage: targetLang,
          writer: writer,
        );
        if (mounted && results.containsKey(sentenceGlobalIndex)) {
          _applyTranslation(sentenceGlobalIndex, results[sentenceGlobalIndex]!);
        }
      } else {
        final translated = await translateWithAI(
          engine: active,
          sentences: [(globalIndex: sentenceGlobalIndex, text: text)],
          sourceLanguage: _bookLanguage,
          targetLanguage: learningLang,
        );
        if (translated.isNotEmpty) {
          await fm.appendTranslation(
            lang: learningLang,
            engineId: active.id,
            priority: priority,
            results: translated,
          );
          if (mounted) _applyTranslation(sentenceGlobalIndex, translated.first.text);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('翻译失败: ${translateErrorMessage(e)}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// 翻译完成后根据当前展示模式决定是否标记为可见
  ///  - on_tap: 添加到 _revealedSentences → 可见
  ///  - immediate: 从 _revealedSentences 移除 → 可见
  void _applyPostTranslationVisibility(int sentenceGlobalIndex) {
    final showMode = ref.read(bilingualShowModeProvider);
    if (showMode == 'on_tap') {
      _revealedSentences.add(sentenceGlobalIndex);
    } else {
      _revealedSentences.remove(sentenceGlobalIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_bookMeta?.title ?? '', style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ]),
      ));
    }
    if (_error != null) {
      return Scaffold(body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16), Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: () { setState(() { _error = null; _isLoading = true; }); _loadBook(); }, child: const Text('重试')),
        ]),
      ));
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── 阅读内容 ──
          Container(
            color: _bgColor,
            child: SafeArea(
              child: _currentChapter == null
                  ? const Center(child: Text('暂无内容', style: TextStyle(color: Colors.grey)))
                  : Column(
                      children: [
                        // 书名行
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(_bookMeta?.title ?? '',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor.withValues(alpha: 0.65)),
                                  overflow: TextOverflow.ellipsis, maxLines: 1,
                                ),
                              ),

                            ],
                          ),
                        ),
                        Expanded(child: _buildReaderContent()),
                      ],
                    ),
            ),
          ),

          // ── 菜单展开时的遮罩 ──
          if (_showMenuPanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () { _saveReadingTime(); _toggleControls(); },
                child: Container(color: Colors.transparent),
              ),
            ),

          // ❌ 退出按钮
          if (_showControls)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8, right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5)),
                  child: ClipOval(child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: const SizedBox.expand(child: Icon(Icons.close, color: Colors.white, size: 24)),
                  )),
                ),
              ),
            ),

          // ⚙️ 设置按钮
          if (_showControls)
            Positioned(
              right: 16, bottom: MediaQuery.of(context).padding.bottom + 80,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (_showMenuPanel) _buildMenuOptions(context)
                else GestureDetector(
                  onTap: () { _saveReadingTime(); setState(() => _showMenuPanel = true); },
                  child: Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5)),
                    child: ClipOval(child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: const SizedBox.expand(child: Icon(Icons.text_fields, color: Colors.white, size: 22)),
                    )),
                  ),
                ),
              ]),
            ),

          // ── 查词面板（内嵌在 reader 的 Stack 中，不阻挡阅读区触摸） ──
          if (_lookupPanelVisible && _lookupWord != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Material(
                type: MaterialType.card,
                color: _bgColor,
                borderRadius: BorderRadius.circular(20),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.33,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: WordLookupPopupContent(
                      word: _lookupWord!,
                      bookId: widget.bookId,
                      bookTitle: _bookMeta?.title,
                      textColor: _textColor,
                      bgColor: _bgColor,
                      onClose: () => _dismissLookupPanel(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderContent() {
    final bilingualEnabled = ref.watch(bilingualEnabledProvider);
    final nativeLang = ref.watch(nativeLanguageProvider);
    final showMode = ref.watch(bilingualShowModeProvider);
    final shouldSwap = bilingualEnabled && _bookLanguage == nativeLang;

    final origStyle = TextStyle(fontSize: _fontSize, color: _textColor,
        height: _lineHeight, letterSpacing: _letterSpacing, fontFamily: 'serif');
    final transStyle = TextStyle(fontSize: _fontSize * 0.88,
        color: _textColor.withValues(alpha: 0.6),
        height: _lineHeight * 0.9, letterSpacing: _letterSpacing,
        fontFamily: 'serif', fontStyle: FontStyle.italic);

    // 重置行 key 计数器, 让 _lineKeys 每 rebuild 循环复用并可清理
    _lineKeyCounter = 0;
    if (!bilingualEnabled) _lineKeys.clear();

    // ── 扁平句子条目列表（供 SliverList 分区懒渲染） ──────────
    // 每种条目:
    //   sep        段落间隔占位
    //   original   原文句子(text + charOffset)或非双语整段
    //   translation 译文行(text + charOffset, 可选展示)
    final items = <_ReaderItem>[];

    for (int bi = 0; bi < _allBlocks.length; bi++) {
      final block = _allBlocks[bi];

      if (bi > 0 && items.isNotEmpty && block.blockType == 'paragraph') {
        items.add(const _ReaderItem.separator());
      }

      block.when(
        paragraph: (paragraph) {
          if (paragraph.sentences.isEmpty) return;
          if (!bilingualEnabled) {
            // 非双语: 整段合并成一条原文(可查词)
            final text = paragraph.sentences.map((s) => s.text).join('');
            items.add(_ReaderItem.original(
                text: text, charOffset: paragraph.sentences.first.charOffset));
            return;
          }
          for (int i = 0; i < paragraph.sentences.length; i++) {
            final s = paragraph.sentences[i];
            final t = _translationMap[s.charOffset] ?? '';
            final hasT = t.isNotEmpty;
            final isRev = _revealedSentences.contains(s.charOffset);
            final showNow = hasT && (showMode == 'on_tap' ? isRev : !isRev);
            final displayOrig = shouldSwap && hasT ? t : s.text;
            final displayTrans = shouldSwap ? s.text : t;

            if (i > 0) items.add(const _ReaderItem.separator());
            items.add(_ReaderItem.original(
                text: displayOrig, charOffset: s.charOffset));

            if (hasT && showNow) {
              items.add(_ReaderItem.translation(
                  text: displayTrans, charOffset: s.charOffset));
            } else {
              items.add(_ReaderItem.placeholder(
                  charOffset: s.charOffset,
                  noTrans: hasT
                      ? false
                      : _noTranslationSentences.contains(s.charOffset)));
            }
          }
        },
        image: (imagePath, altText) {
          final file = File(p.join(ref.read(libraryPathProvider), 'books',
              widget.bookId, 'images', p.basename(imagePath)));
          items.add(_ReaderItem.image(file: file, altText: altText));
        },
      );
    }

    // 底部留白
    items.add(const _ReaderItem.separator());

    // 译文高度缓存同步到条目数(用于提前预计算展开高, 避免测量抖动)
    if (_itemHeightCache.length < items.length) {
      final grow = List<double>.filled(items.length - _itemHeightCache.length, 0);
      _itemHeightCache.addAll(grow);
    }

    // ── 点击命中: 用 TextPainter 精确算出点击点所在的词 ──────
    Widget row(BuildContext ctx, int i, _ReaderItem it) => it.when(
      separator: () => SizedBox(width: double.infinity,
          height: i > 0 ? 4 : 12),
      original: (text, charOffset) => _buildOriginalRow(
          text, charOffset, origStyle, bilingualEnabled),
      translation: (text, charOffset) => _buildTranslationRow(
          text, charOffset, transStyle, shouldSwap),
      placeholder: (charOffset, noTrans) =>
          _buildTransPlaceholder(index: charOffset, hasT: false, noTrans: noTrans),
      image: (file, altText) => (file != null && file.existsSync())
          ? ClipRRect(borderRadius: BorderRadius.circular(4),
            child: Image.file(file, fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _imagePlaceholder(altText)))
          : _imagePlaceholder(altText),
    );

    // 清理不再使用的行 key, 防止滚动加载多章后无界增长
    if (_lineKeys.length > _lineKeyCounter * 2 + 64) {
      _lineKeys.removeWhere((k, _) => k >= _lineKeyCounter);
    }
    if (_translationKeys.length > 4096) {
      _translationKeys.removeWhere(
          (k, v) => v.currentContext?.findRenderObject() == null);
    }

    // ── 不足一屏滚动手势 + 章节边界加载 + 分区懒渲染 ──────────
    // SelectionArea 提供跨句子的长按复制(默认上下文菜单含“复制”),
    // 替代句子级 SelectableText, 大大减少 EditableText 数量。
    return SelectionArea(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification &&
              _scrollController.hasClients &&
              _scrollController.position.maxScrollExtent < 1.0) {
            if (notification.direction == ScrollDirection.reverse &&
                !_isAppending) {
              final next = _loadedUpToChapter + 1;
              if (next < _chapterCount) {
                _isAppending = true;
                _loadChapter(next, direction: LoadDirection.append);
              }
            } else if (notification.direction == ScrollDirection.forward &&
                !_isPrepending) {
              final prev = _loadedDownToChapter - 1;
              if (prev >= 0) {
                _isPrepending = true;
                _loadChapter(prev, direction: LoadDirection.prepend);
              }
            }
          }
          return false;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPtrDown,
          onPointerUp: _onPtrUp,
          onPointerCancel: _onPtrCancel,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.builder(
                  // 分区懒渲染: 只 build 可视及邻近范围(默认 cacheExtent),
                  // 长文/多章不会一次性构建全部句子, 大幅降低布局开销。
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final it = items[i];
                    return _recordHeight(
                      i,
                      row(ctx, i, it),
                    );
                  },
                ),
              ),
              // 底部留白
              SliverToBoxAdapter(
                  child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
    );
  }

  // ── 高度缓存记录: 每行 build 后把实际高度写入 _itemHeightCache ──
  Widget _recordHeight(int i, Widget child) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // constraints.maxHeight 在 SliverList 中代表可用区间; 不作为最终高度。
        // 用 Builder + post-frame 读取 child 真实渲染高度写入缓存, 供后续预计算与锚点。
        return Builder(
          builder: (ctx) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final rc = ctx.findRenderObject();
              if (rc is RenderBox && rc.hasSize) {
                final h = rc.size.height;
                if (i < _itemHeightCache.length &&
                    _itemHeightCache[i] != h) {
                  _itemHeightCache[i] = h;
                }
              }
            });
            return child;
          },
        );
      },
    );
  }

  // 查词面板状态（内嵌在 reader 的 Stack 中，不使用 OverlayEntry）
  bool _lookupPanelVisible = false;
  String? _lookupWord;

  // 由内部 GestureDetector 触发的查词操作，阻止外层的 _onPtrUp 重复处理
  bool _wordTappedFromGesture = false;

  // 每行文本的持久化 GlobalKey（跨 rebuild 保持引用）
  final Map<int, GlobalKey> _lineKeys = {};
  int _lineKeyCounter = 0;

  // ── 指针点击检测（呼出菜单+查词） ──
  bool _ptrDown = false;
  Offset _ptrDownPos = Offset.zero;
  DateTime _ptrDownTime = DateTime.now();

  void _onPtrDown(PointerDownEvent e) {
    _ptrDown = true;
    _ptrDownPos = e.position;
    _ptrDownTime = DateTime.now();
  }

  void _onPtrUp(PointerUpEvent e) {
    if (!_ptrDown) return;
    _ptrDown = false;
    final elapsed = DateTime.now().difference(_ptrDownTime).inMilliseconds;
    final moved = (e.position - _ptrDownPos).distance;
    if (elapsed >= 300 || moved >= 12) return;

    // 如果内部 GestureDetector 已经处理了此点击，跳过
    final wasWordTap = _wordTappedFromGesture;
    _wordTappedFromGesture = false;
    if (wasWordTap) return;

    // 无论是否双语模式，先检查是否命中子组件手势（译文占位框）
    if (_hitOnChildGestureHandler(e.position)) return;

    if (ref.read(bilingualEnabledProvider)) {
      // 双语模式：退路方案 — 通过全局 hitTest 提取单词
      final hit = _extractWordAtPoint(e.position);
      if (hit != null && hit.word.length >= 2) {
        setState(() {
          _highlightedWord = hit.word;
          _highlightedText = hit.text;
          _highlightWordStart = hit.start;
          _highlightWordEnd = hit.end;
        });
        _showWordLookup(hit.word);
        return;
      }
      // 点击字形（SelectableText）→ 交 SelectableText 处理，不呼菜单
      if (_onTextGlyph(e.position)) return;
      // 点击空白 → 呼出菜单
      _clearHighlight();
      _saveReadingTime();
      _toggleControls(showMenuDirectly: true);
      return;
    }

    // 非双语模式
    // 点击字形（SelectableText 在点击字形时路径会有 InlineSpan）→ 交 SelectableText
    if (_onTextGlyph(e.position)) return;
    // 空白区域 → 呼出菜单
    _saveReadingTime();
    _toggleControls(showMenuDirectly: true);
  }

  void _onPtrCancel(PointerCancelEvent e) {
    _ptrDown = false;
  }

  /// 检测点击位置是否落在文本字形上（非空白区域）
  bool _onTextGlyph(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final result = BoxHitTestResult();
    final local = box.globalToLocal(globalPos);
    if (!(box.hitTest(result, position: local))) return false;
    for (final entry in result.path) {
      if (entry.target is InlineSpan) return true;
    }
    return false;
  }

  /// 从点击位置提取单词。
  /// getPositionForPoint 吸附到最近字符，然后扩展为完整单词。
  /// 直接使用 _extractWordAtOffset 返回的 start/end，
  /// 避免 indexOf 匹配到重复词的错误实例。
  ///
  /// iOS/Impeller 下 getPositionForPoint 对高行高、多行文本可能吸附到
  /// 相邻行/相邻词，导致“点到 A 词却查 B 词”。这里用 getBoxesForSelection
  /// 反向校验：取候选字符的包围盒，只有当点击点确实落在该字符的水平区间内
  /// 才接受；否则跳过当前 RenderEditable 继续尝试下一个（双语模式下
  /// 同一屏有原文 + 译文多个文本节点）。
  /// 返回 (fullText, word, start, end) 或 null。
  ({String text, String word, int start, int end})? _extractWordAtPoint(
      Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    final local = box.globalToLocal(globalPos);
    if (!(box.hitTest(result, position: local))) return null;

    // 遍历所有命中的 RenderEditable（双语模式下可能多个文本节点叠加）
    for (final entry in result.path) {
      if (entry.target is! RenderEditable) continue;
      final target = entry.target as RenderEditable;
      final textEv = target.text;
      if (textEv == null) continue;
      final text = textEv.toPlainText();
      if (text.isEmpty) continue;
      try {
        final editableLocal = target.globalToLocal(globalPos);
        final offset = target.getPositionForPoint(editableLocal).offset;
        if (offset < 0 || offset >= text.length) continue;

        // 用字符包围盒反向校验, 纠正 iOS 吸附偏差
        final boxes = target.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        );
        bool inside = false;
        for (final b in boxes) {
          // 用字符中心点比较, 避免只命中文字顶部/底部的空白区
          final charBox = b.toRect();
          final yMin = charBox.top - 4.0;
          final yMax = charBox.bottom + 4.0;
          if (editableLocal.dx >= charBox.left - 2.0 &&
              editableLocal.dx <= charBox.right + 2.0 &&
              editableLocal.dy >= yMin &&
              editableLocal.dy <= yMax) {
            inside = true;
            break;
          }
        }
        if (!inside) continue; // 点在其他词/其他行, 试下一个文本节点

        final result_ = _extractWordAtOffset(text, offset);
        if (result_ == null || result_.word.length < 2) continue;
        return (text: text, word: result_.word,
            start: result_.start, end: result_.end);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  ({int start, int end, String word})? _extractWordAtOffset(
      String text, int offset) {
    if (text.isEmpty || offset < 0 || offset >= text.length) return null;

    // 定义单词字符集：字母、数字、连字符、撇号
    bool isWordChar(String ch) {
      final code = ch.codeUnitAt(0);
      return (code >= 0x41 && code <= 0x5A) || // A-Z
          (code >= 0x61 && code <= 0x7A) || // a-z
          code == 0x27 || // '
          code == 0x2D; // -
    }

    // 检查点击位置本身是否是单词字符
    if (!isWordChar(text[offset])) {
      // 中文等非字母文字：尝试取单个字符
      if (text[offset].trim().isNotEmpty) {
        return (
          start: offset,
          end: offset + 1,
          word: text[offset],
        );
      }
      return null;
    }

    // 向左扩展
    int start = offset;
    while (start > 0 && isWordChar(text[start - 1])) {
      start--;
    }

    // 向右扩展
    int end = offset;
    while (end < text.length && isWordChar(text[end])) {
      end++;
    }

    if (start >= end) return null;
    return (
      start: start,
      end: end,
      word: text.substring(start, end),
    );
  }

  /// 弹出查词窗口 — 在 reader 的 Stack 中内嵌显示
  void _showWordLookup(String word) {
    if (word.isEmpty) return;
    setState(() {
      _lookupWord = word;
      _lookupPanelVisible = true;
    });
  }

  void _dismissLookupPanel() {
    if (!_lookupPanelVisible && _lookupWord == null) return;
    setState(() {
      _lookupPanelVisible = false;
      _lookupWord = null;
    });
    if (mounted) _clearHighlight();
  }

  void _clearHighlight() {
    setState(() {
      _highlightedWord = null;
      _highlightedText = null;
      _highlightWordStart = null;
      _highlightWordEnd = null;
    });
  }

  /// 判断全局坐标 [globalPos] 是否落在有独立手势的子组件上（如译文占位框的
  /// GestureDetector），此时不呼出菜单，由子组件自己处理点击。
  ///
  /// 只有路径中同时有多个 RenderPointerListener 并且其中至少有一个是
  /// 子组件的 RenderPointerListener（即不是 Listener 自身）且没有
  /// RenderEditable 文本组件时，才判定为有独立手势的子组件。
  /// 纯图片页面（无文本）时路径中只有 Listener+ScrollView 的 Listener，
  /// 需要让点击通过呼出菜单。
  bool _hitOnChildGestureHandler(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final result = BoxHitTestResult();
    final local = box.globalToLocal(globalPos);
    if (!(box.hitTest(result, position: local))) return false;
    bool hasRenderEditable = false;
    int pointerListenerCount = 0;
    for (final entry in result.path) {
      if (entry.target is RenderPointerListener) {
        pointerListenerCount++;
      }
      if (entry.target is RenderEditable) {
        hasRenderEditable = true;
      }
    }
    // 有 >=3 个 RenderPointerListener 且路径中无 RenderEditable
    // 说明点击落在有自定义手势子组件（译文占位框：自身 GestureDetector +
    // BackdropFilter）上，且该区域无文本。
    // 只有 2 个时是 Listener 自身 + ScrollView，属于纯空白/图片区域，
    // 应该呼出菜单而不是拦截。
    return pointerListenerCount >= 3 && !hasRenderEditable;
  }

  /// 毛玻璃占位框，高度 ≈ 一行译文，点击展开译文
  Widget _buildTransPlaceholder({required int index, required bool hasT, required bool noTrans}) {
    final placeholderHeight = _fontSize * _lineHeight * 0.9;
    // 占满整宽。
    // 注意: 这里刻意不用 BackdropFilter(毛玻璃)——每个未翻译句子都会实例化一个
    // BackdropFilter + 高斯模糊, 触发 GPU saveLayer 并随滚动反复逐句重绘,
    // 是双语模式翻页卡顿的主要来源。改用纯色背景占位, 不触发 saveLayer。
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _tapTranslationArea(index),
        child: Container(
          height: placeholderHeight,
          decoration: BoxDecoration(
            color: _textColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _textColor.withValues(alpha: 0.1)),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            noTrans ? '暂无对应译文' : '点击显示译文',
            style: TextStyle(
              fontSize: _fontSize * 0.85,
              color: _textColor.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder(String? altText) {
    return Container(height: 200, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.image, size: 48, color: Colors.grey),
        if (altText != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(altText, style: const TextStyle(color: Colors.grey))),
      ])),
    );
  }

  /// 原文行: 轻量 Text + TextPainter 命中检测查词 (不依赖 SelectableText)。
  /// 仅双语模式下需要点词查词; 非双语整段用普通 Text, 由外层 SelectionArea
  /// 提供复制。
  Widget _buildOriginalRow(
      String text, int charOffset, TextStyle style, bool lookupEnabled) {
    // 高亮渲染
    Widget base;
    if (_highlightedWord != null &&
        _highlightedText == text &&
        _highlightWordStart != null) {
      final spans = <TextSpan>[];
      if (_highlightWordStart! > 0) {
        spans.add(TextSpan(
            text: text.substring(0, _highlightWordStart!), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(_highlightWordStart!, _highlightWordEnd!),
        style: style.copyWith(
            backgroundColor: _textColor.withValues(alpha: 0.25)),
      ));
      if (_highlightWordEnd! < text.length) {
        spans.add(TextSpan(
            text: text.substring(_highlightWordEnd!), style: style));
      }
      base = Text.rich(TextSpan(children: spans, style: style),
          maxLines: null);
    } else {
      base = Text(text, style: style, maxLines: null);
    }

    // 查词: 仅双语模式下对原文行启用 Listener + TextPainter 命中
    if (lookupEnabled && text.trim().isNotEmpty) {
      final keyId = _lineKeyCounter++;
      final lineKey = _lineKeys.putIfAbsent(keyId, () => GlobalKey());
      return RepaintBoundary(
        child: Listener(
          onPointerUp: (event) {
            final elapsed =
                DateTime.now().difference(_ptrDownTime).inMilliseconds;
            if (!_ptrDown || elapsed >= 300 ||
                (event.position - _ptrDownPos).distance >= 12) {
              return;
            }
            if (!ref.read(bilingualEnabledProvider)) return;
            final renderBox =
                lineKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox == null) return;
            final localPos = renderBox.globalToLocal(event.position);
            final tp = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: renderBox.size.width);
            if (localPos.dx < 0 || localPos.dx > tp.width ||
                localPos.dy < 0 || localPos.dy > tp.height) {
              return;
            }
            final charOffset_ = tp.getPositionForOffset(localPos).offset;
            if (charOffset_ < 0 || charOffset_ >= text.length) return;
            final result_ = _extractWordAtOffset(text, charOffset_);
            if (result_ == null || result_.word.length < 2) return;
            _wordTappedFromGesture = true;
            setState(() {
              _highlightedWord = result_.word;
              _highlightedText = text;
              _highlightWordStart = result_.start;
              _highlightWordEnd = result_.end;
            });
            _showWordLookup(result_.word);
          },
          child: KeyedSubtree(key: lineKey, child: base),
        ),
      );
    }
    return RepaintBoundary(child: base);
  }

  /// 译文行: 轻量 Text, 仅展示, 不参与查词。
  /// 用 _translationKeys[charOffset] 提供锚点, 供展开/折叠滚动补偿。
  Widget _buildTranslationRow(
      String text, int charOffset, TextStyle style, bool _) {
    final key = _translationKeys.putIfAbsent(charOffset, () => GlobalKey());
    return RepaintBoundary(
      child: KeyedSubtree(
        key: key,
        child: Text(text, style: style, maxLines: null),
      ),
    );
  }

  Widget _buildMenuOptions(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(width: 200,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _MenuTile(icon: Icons.menu_book_rounded, title: '目录', subtitle: 'Chapter ${_currentChapterIndex + 1} / $_chapterCount', trailing: Icon(Icons.list, color: Colors.white.withValues(alpha: 0.7), size: 20),
              onTap: () { setState(() => _showMenuPanel = false); _showChapterTOC(); }),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            _MenuTile(icon: Icons.palette_outlined, title: '主题与设置', subtitle: '字体 / 颜色 / 行高',
              onTap: () { setState(() => _showMenuPanel = false); _showReaderSettings(); }),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            _MenuTile(icon: Icons.language, title: '双语阅读', subtitle: _bilingualStatus(),
              onTap: () { setState(() => _showMenuPanel = false); _showBilingualSettingsInReader(); }),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            _MenuTile(icon: Icons.translate, title: '翻译', subtitle: '翻译当前章节',
              onTap: () { setState(() => _showMenuPanel = false); _showTranslateOptions(); }),

          ]),
        ),
      ),
    );
  }

  // ── 目录 ──
  void _showChapterTOC() {
    final reader = _reader;
    if (reader == null) return;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_bookMeta?.title ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (_bookMeta?.author.isNotEmpty == true) Text(_bookMeta!.author, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
          ])),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
            Text('Chapter ${_currentChapterIndex + 1} / $_chapterCount', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('${_chapterCount > 0 ? ((_currentChapterIndex + 1) * 100 ~/ _chapterCount) : 0}%', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: _chapterCount > 0 ? (_currentChapterIndex + 1) / _chapterCount : 0.0, minHeight: 4))),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(vertical: 4), itemCount: _chapterCount,
            itemBuilder: (ctx, i) {
              final ch = reader.readChapter(i);
              final title = ch?.title.isNotEmpty == true ? ch!.title : 'Chapter ${i + 1}';
              final isCurrent = i == _currentChapterIndex;
              return ListTile(
                selected: isCurrent,
                selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                leading: Icon(isCurrent ? Icons.bookmark : Icons.menu_book_outlined, size: 20, color: isCurrent ? Theme.of(context).colorScheme.primary : null),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400, color: isCurrent ? Theme.of(context).colorScheme.primary : null)),
                onTap: () { Navigator.pop(ctx); _loadChapter(i); },
              );
            },
          )),
        ]),
      ),
    );
  }

  // ── 主题与设置 ──
  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('阅读设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 48, child: Text('字号', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Slider(value: _fontSize, min: 12, max: 32, onChanged: (v) { setSheetState(() => _fontSize = v); setState(() {}); })),
              SizedBox(width: 40, child: Text('${_fontSize.round()}', style: const TextStyle(fontSize: 13))),
            ]),
            Row(children: [
              SizedBox(width: 48, child: Text('行高', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Slider(value: _lineHeight, min: 1.0, max: 2.8, divisions: 18, onChanged: (v) { setSheetState(() => _lineHeight = v); setState(() {}); })),
              SizedBox(width: 40, child: Text(_lineHeight.toStringAsFixed(1), style: const TextStyle(fontSize: 13))),
            ]),
            Row(children: [
              SizedBox(width: 48, child: Text('间距', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Slider(value: _letterSpacing, min: 0.0, max: 3.0, divisions: 30, onChanged: (v) { setSheetState(() => _letterSpacing = v); setState(() {}); })),
              SizedBox(width: 40, child: Text(_letterSpacing.toStringAsFixed(1), style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(width: 48, child: Text('预加载', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Slider(value: _preloadCount.toDouble(), min: 1, max: 20, divisions: 19, onChanged: (v) { setSheetState(() => _preloadCount = v.round()); setState(() {}); })),
              SizedBox(width: 40, child: Text('${_preloadCount}章', style: const TextStyle(fontSize: 13))),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _ThemeBtn(color: Colors.white, label: '浅色', onTap: () { setSheetState(() { _textColor = Colors.black87; _bgColor = Colors.white; }); setState(() {}); }),
              _ThemeBtn(color: const Color(0xFFFFF8E1), label: '护眼', onTap: () { setSheetState(() { _textColor = Colors.brown[800]!; _bgColor = const Color(0xFFFFF8E1); }); setState(() {}); }),
              _ThemeBtn(color: const Color(0xFF1E1E1E), label: '深色', onTap: () { setSheetState(() { _textColor = Colors.white70; _bgColor = const Color(0xFF1E1E1E); }); setState(() {}); }),
            ]),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    ).whenComplete(() => _saveReaderSettings());
  }

  // ── 双语阅读 ──
  String _bilingualStatus() {
    final enabled = ref.watch(bilingualEnabledProvider);
    if (!enabled) return '已关闭';
    final layout = ref.watch(bilingualLayoutProvider);
    final learning = languageNames[ref.watch(bilingualLearningLanguageProvider)] ?? 'English';
    final ln = layout == 'alternating' ? '交替' : layout == 'paragraph' ? '段落后' : '分栏';
    return '$learning · $ln';
  }

  void _showBilingualSettingsInReader() {
    final layoutOptions = { 'alternating': '交替显示', 'paragraph': '段落后显示', 'side_by_side': '左右分栏' };
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Expanded(child: Text('双语阅读', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
              const SizedBox(height: 8),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('启用双语阅读'), subtitle: const Text('阅读时显示原文与译文'),
                value: ref.watch(bilingualEnabledProvider),
                onChanged: (v) { ref.read(bilingualEnabledProvider.notifier).state = v; LibraryDatabase().setSetting('bilingual_enabled', v ? '1' : '0'); setSheetState(() {}); }),
              // 译文展示方式
              const SizedBox(height: 4),
              const Text('译文展示', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              RadioListTile<String>(contentPadding: EdgeInsets.zero, title: const Text('立即展示'), subtitle: const Text('译文直接跟随原文显示'), value: 'immediate',
                groupValue: ref.watch(bilingualShowModeProvider),
                onChanged: (v) { if (v != null) { ref.read(bilingualShowModeProvider.notifier).state = v; LibraryDatabase().setSetting('bilingual_show_mode', v); setSheetState(() {}); }}),
              RadioListTile<String>(contentPadding: EdgeInsets.zero, title: const Text('点击展示'), subtitle: const Text('点击译文区域后才显示译文'), value: 'on_tap',
                groupValue: ref.watch(bilingualShowModeProvider),
                onChanged: (v) { if (v != null) { ref.read(bilingualShowModeProvider.notifier).state = v; LibraryDatabase().setSetting('bilingual_show_mode', v); setSheetState(() {}); }}),
              const Divider(),
              const Text('学习语言', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Row(children: [
                Icon(Icons.menu_book, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(languageNames[ref.watch(bilingualLearningLanguageProvider)] ?? 'English')),
                TextButton(onPressed: () { _showLanguagePicker(ref.watch(bilingualLearningLanguageProvider), (lang) { ref.read(bilingualLearningLanguageProvider.notifier).state = lang; LibraryDatabase().setSetting('bilingual_learning', lang); }); }, child: const Text('更改')),
              ]),
              const SizedBox(height: 12),
              const Text('阅读习惯', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
                  Expanded(child: Text('默认书籍原文语言为学习语言。如果书籍语言与母语一致，则会自动反转：将译文作为原文，书籍原文做译文展示。',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4))),
                ]),
              ),
              ...layoutOptions.entries.map((e) => RadioListTile<String>(contentPadding: EdgeInsets.zero, title: Text(e.value), subtitle: Text(_layoutSubtitle(e.key)),
                value: e.key, groupValue: ref.watch(bilingualLayoutProvider),
                onChanged: (v) { if (v != null) { ref.read(bilingualLayoutProvider.notifier).state = v; LibraryDatabase().setSetting('bilingual_layout', v); setSheetState(() {}); }})),
            ]),
          ),
        ),
      ),
    );
  }

  String _layoutSubtitle(String layout) {
    switch (layout) {
      case 'alternating': return '原文与译文交替出现';
      case 'paragraph': return '每段原文后紧跟译文';
      case 'side_by_side': return '原文在左，译文在右';
      default: return '';
    }
  }

  void _showLanguagePicker(String current, ValueChanged<String> onSelected) {
    final entries = languageNames.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    showDialog(context: context, builder: (ctx) => SimpleDialog(title: const Text('选择语言'),
      children: [for (final e in entries) RadioListTile<String>(title: Text(e.value), subtitle: Text(e.key.toUpperCase()), value: e.key, groupValue: current,
        onChanged: (v) { if (v != null) { onSelected(v); Navigator.pop(ctx); } })],
    ));
  }

  // ── 翻译 ──
  void _showTranslateOptions() {
    showModalBottomSheet(context: context, builder: (ctx) => Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('翻译', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.auto_awesome), label: const Text('翻译当前章节'), onPressed: () { Navigator.pop(ctx); _translateCurrentChapter(); })),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.translate), label: const Text('翻译全部章节'), onPressed: () { Navigator.pop(ctx); _translateAllChapters(); })),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.cleaning_services_outlined), label: const Text('清除翻译缓存'), onPressed: () { Navigator.pop(ctx); _clearTranslationCache(); })),
      ]),
    ));
  }

  void _translateCurrentChapter() {
    _performTranslation(isFullBook: false);
  }

  void _translateAllChapters() {
    _performTranslation(isFullBook: true);
  }

  Future<void> _performTranslation({required bool isFullBook}) async {
    final reader = _reader;
    if (reader == null) return;

    final learningLang = ref.read(bilingualLearningLanguageProvider);

    // 检查当前使用的翻译引擎
    final activeEngine = ref.read(activeTranslationEngineProvider);
    final isLocalEngine = activeEngine?.id == 'local_bergamot';

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在翻译...'), behavior: SnackBarBehavior.floating),
    );

    final libraryPath = ref.read(libraryPathProvider);

    // 收集需要翻译的句子
    final allSentences = <({int globalIndex, String text})>[];
    final chapters = isFullBook
        ? List.generate(_chapterCount, (i) => i)
        : [_currentChapterIndex];
    for (final chIdx in chapters) {
      final ch = reader.readChapter(chIdx);
      if (ch == null) continue;
      for (final block in ch.blocks) {
        block.when(
          paragraph: (p) {
            for (final s in p.sentences) {
              allSentences.add((globalIndex: s.charOffset, text: s.text));
            }
          },
          image: (_, _) {},
        );
      }
    }

    final engines = ref.read(translationEnginesProvider);
    final active = engines.isNotEmpty ? engines.first : null;
    debugPrint('[翻译] activeEngine=${active?.id} isLocalEngine=$isLocalEngine');
    if (active == null) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未设置翻译引擎'), behavior: SnackBarBehavior.floating)); }
      return;
    }

    final priority = engines.indexOf(active);
    final fm = TranslationFileManager(
        p.join(libraryPath, 'books', widget.bookId), bookId: widget.bookId);

    // 开始通知（结束通知在完成/失败时发送，形成有头有尾的提示）
    LibraryDatabase().addNotification(
      type: 'translation_started',
      title: '开始翻译',
      body: '「${_bookMeta?.title ?? ''}」开始翻译 ${allSentences.length} 句',
      bookId: widget.bookId,
    );

    try {
      if (isLocalEngine) {
        final nativeLang = ref.read(nativeLanguageProvider);
        final (sourceLang, targetLang) = resolveLocalDirection(
          bookLanguage: _bookLanguage,
          nativeLanguage: nativeLang,
          learningLanguage: learningLang,
        );

        if (sourceLang != 'en' && targetLang != 'en') {
          throw Exception('本地离线翻译仅支持英语与其他语言之间的翻译，当前语言对不受支持');
        }

        final nonEnglishLang = sourceLang == 'en' ? targetLang : sourceLang;
        if (!await ensureBergamotModel(context, ref, nonEnglishLang)) return;

        final service = LocalTranslationService(bookId: widget.bookId, libraryPath: libraryPath);
        final writer = BatchFileWriter(fm, targetLang, active.id, priority, totalCount: allSentences.length);
        final results = await service.translateParagraph(
          sentences: allSentences,
          sourceLanguage: sourceLang, targetLanguage: targetLang,
          writer: writer,
        );
        if (mounted) {
          setState(() => _translationMap.addAll(results));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('翻译完成: ${results.length} 句'), behavior: SnackBarBehavior.floating));
          final db = LibraryDatabase();
          await db.addNotification(type: 'translation', title: '翻译完成', body: '「${_bookMeta?.title ?? ''}」已翻译 ${results.length} 句', bookId: widget.bookId);
        }
      } else {
        final translated = await translateWithAI(engine: active, sentences: allSentences,
            sourceLanguage: _bookLanguage, targetLanguage: learningLang);
        if (translated.isNotEmpty) {
          await fm.appendTranslation(lang: learningLang, engineId: active.id, priority: priority, results: translated);
        }
        if (mounted) {
          setState(() {
            for (final r in translated) {
              _translationMap[r.globalIndex] = r.text;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('翻译完成: ${translated.length} 句'), behavior: SnackBarBehavior.floating));
          final db = LibraryDatabase();
          await db.addNotification(type: 'translation', title: '翻译完成', body: '「${_bookMeta?.title ?? ''}」已翻译 ${translated.length} 句', bookId: widget.bookId);
        }
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('翻译失败: ${translateErrorMessage(e)}'), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4))); }
    }
  }

  void _clearTranslationCache() {
    final learningLang = ref.read(bilingualLearningLanguageProvider);
    final libraryPath = ref.read(libraryPathProvider);
    final service = LocalTranslationService(
      bookId: widget.bookId,
      libraryPath: libraryPath,
    );
    service.clearTranslation(learningLang);
    setState(() => _translationMap.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('翻译缓存已清除'), behavior: SnackBarBehavior.floating),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  const _MenuTile({required this.icon, required this.title, this.subtitle, this.trailing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            if (subtitle != null && subtitle!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ])),
          trailing ?? const SizedBox.shrink(),
        ]),
      ),
    );
  }
}

class _ThemeBtn extends StatelessWidget {
  final Color color; final String label; final VoidCallback onTap;
  const _ThemeBtn({required this.color, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
/// 阅读器扁平条目模型: 支持 SliverList 分区懒渲染。
class _ReaderItem {
  final String type; // separator / original / translation / placeholder / image
  final String text;
  final int charOffset;
  final bool noTrans;
  final File? file;
  final String? altText;

  const _ReaderItem._({
    required this.type,
    this.text = '',
    this.charOffset = -1,
    this.noTrans = false,
    this.altText,
    this.file,
  });

  // 每种工厂显式传默认值, 保证可选参数默认值都是编译期常量
  const _ReaderItem.separator() : this._(type: 'separator');
  factory _ReaderItem.original(
          {required String text, required int charOffset}) =>
      _ReaderItem._(type: 'original', text: text, charOffset: charOffset);
  factory _ReaderItem.translation(
          {required String text, required int charOffset}) =>
      _ReaderItem._(type: 'translation', text: text, charOffset: charOffset);
  factory _ReaderItem.placeholder(
          {required int charOffset, required bool noTrans}) =>
      _ReaderItem._(type: 'placeholder',
          charOffset: charOffset, noTrans: noTrans);
  factory _ReaderItem.image({required File file, String? altText}) =>
      _ReaderItem._(type: 'image', file: file, altText: altText);

  R when<R>({
    required R Function() separator,
    required R Function(String text, int charOffset) original,
    required R Function(String text, int charOffset) translation,
    required R Function(int charOffset, bool noTrans) placeholder,
    required R Function(File? file, String? altText) image,
  }) {
    switch (type) {
      case 'separator':
        return separator();
      case 'original':
        return original(text, charOffset);
      case 'translation':
        return translation(text, charOffset);
      case 'placeholder':
        return placeholder(charOffset, noTrans);
      case 'image':
        return image(file, altText);
      default:
        return separator();
    }
  }
}

