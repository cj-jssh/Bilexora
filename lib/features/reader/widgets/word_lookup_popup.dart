import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/services/dictionary_service.dart';

/// 查词结果卡片（仅内容，不包含外层 Material/弹窗/动画）
/// 由调用方嵌入自定义路由动画中。
class WordLookupPopupContent extends StatefulWidget {
  final String word;
  final String bookId;
  final String? bookTitle;
  final Color textColor;
  final Color bgColor;
  final VoidCallback? onClose;

  const WordLookupPopupContent({
    super.key,
    required this.word,
    required this.bookId,
    this.bookTitle,
    this.textColor = Colors.black87,
    this.bgColor = Colors.white,
    this.onClose,
  });

  @override
  State<WordLookupPopupContent> createState() => _WordLookupPopupContentState();
}

class _WordLookupPopupContentState extends State<WordLookupPopupContent> {
  WordDefinition? _definition;
  bool _isLoading = true;
  String? _error;
  bool _saved = false;
  bool _isSpeaking = false;
  Timer? _debounce;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(WordLookupPopupContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 100), () {
        setState(() {
          _definition = null;
          _isLoading = true;
          _error = null;
          _saved = false;
        });
        _lookup();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _lookup() async {
    try {
      final def = await DictionaryService.lookup(widget.word);
      if (mounted) {
        setState(() {
          _definition = def;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveToVocabulary() async {
    if (_definition == null) return;
    try {
      await DictionaryService.saveToVocabulary(
        word: widget.word,
        definition: _definition!,
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
      );
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyWord() {
    Clipboard.setData(ClipboardData(text: widget.word));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _playAudio() async {
    if (_isSpeaking) return;
    setState(() => _isSpeaking = true);
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.4);
      await _tts.speak(widget.word);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('语音播放失败'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 顶部颜色条 ──
        Container(
          height: 4,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.secondary,
              ],
            ),
          ),
        ),
        // ── 标题行 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.word,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: widget.textColor,
                      ),
                    ),
                    if (_definition?.phonetic != null &&
                        _definition!.phonetic!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _definition!.phonetic!,
                          style: TextStyle(
                            fontSize: 16,
                            color: widget.textColor.withValues(alpha: 0.55),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 操作按钮
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconBtn(
                    icon: _isSpeaking
                        ? Icons.volume_up
                        : Icons.volume_up_outlined,
                    tooltip: _isSpeaking ? '播放中' : '朗读',
                    onTap: _isSpeaking ? null : _playAudio,
                    textColor: _isSpeaking
                        ? theme.colorScheme.primary
                        : widget.textColor,
                  ),
                  _IconBtn(
                    icon: Icons.copy_rounded,
                    tooltip: '复制',
                    onTap: _copyWord,
                    textColor: widget.textColor,
                  ),
                  _IconBtn(
                    icon: _saved ? Icons.bookmark : Icons.bookmark_border_rounded,
                    tooltip: _saved ? '已收藏' : '收藏到生词本',
                    onTap: _saved ? null : _saveToVocabulary,
                    textColor: _saved
                        ? theme.colorScheme.primary
                        : widget.textColor,
                  ),
                  _IconBtn(
                    icon: Icons.close,
                    tooltip: '关闭',
                    onTap: widget.onClose ?? () => Navigator.maybePop(context),
                    textColor: widget.textColor,
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 24),

        // ── 主体内容 ──
        Flexible(
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _error != null
                  ? _buildError(theme)
                  : _buildDefinitions(theme),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 48,
              color: widget.textColor.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('未找到释义',
              style: TextStyle(
                  fontSize: 16,
                  color: widget.textColor.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Text('「${widget.word}」可能不在词典中',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: widget.textColor.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _buildDefinitions(ThemeData theme) {
    final def = _definition;
    if (def == null) return const SizedBox.shrink();

    if (def.meanings.isEmpty) {
      return _buildError(theme);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      shrinkWrap: true,
      children: [
        for (int i = 0; i < def.meanings.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _buildMeaningCard(theme, def.meanings[i], i),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMeaningCard(ThemeData theme, Meaning meaning, int index) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              meaning.partOfSpeech.isNotEmpty
                  ? meaning.partOfSpeech
                  : '其他',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int j = 0; j < meaning.definitions.length; j++) ...[
            if (j > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${j + 1}.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          meaning.definitions[j].definition,
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.textColor,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (meaning.definitions[j].example != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 20),
                      child: Text(
                        '“${meaning.definitions[j].example}”',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.textColor.withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (meaning.definitions[j].synonyms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 20),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text('同义: ',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: widget.textColor
                                      .withValues(alpha: 0.4))),
                          ...meaning.definitions[j].synonyms.take(4).map(
                                (syn) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer
                                        .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(syn,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color textColor;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onTap,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22,
              color: textColor.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}