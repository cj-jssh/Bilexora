import 'dart:math';

/// 文本工具类
class TextUtils {
  TextUtils._();

  /// 引号配对关系
  static const _openQuotes = <String, String>{
    '"': '"',
    "'": "'",
    '\u201C': '\u201D', // " → "
    '\u2018': '\u2019', // ' → '
    '\u300C': '\u300D', // 「 → 」
    '\u300E': '\u300F', // 『 → 』
    '\u300A': '\u300B', // 《 → 》
  };

  static const _closingQuoteSet = <String>{
    '"', "'", '\u201D', '\u2019', '\u300D', '\u300F', '\u300B',
  };

  /// 将文本分割成句子
  ///
  /// 规则：
  /// - 中文以 。？！结尾分割
  /// - 英文以 . ! ? 结尾分割，排除缩写和数字小数点
  /// - **引号/括号内的标点不分割**（避免"他说："被截断）
  /// - 省略号 ... …… 不分割
  /// - 连续标点 !? ?! 合并为一个结尾
  static List<String> splitSentences(String text) {
    if (text.isEmpty) return [];

    final result = <String>[];
    final buffer = StringBuffer();
    // 引号栈：记录当前打开的引号类型
    final quoteStack = <String>[];

    const abbreviations = <String>{
      'mr', 'mrs', 'ms', 'dr', 'st', 'ave', 'etc', 'eg', 'ie', 'vs',
      'inc', 'ltd', 'corp', 'dept', 'est', 'govt', 'jr', 'sr', 'no',
      'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'oct',
      'nov', 'dec', 'rev', 'ed', 'vol', 'p', 'pp', 'ch',
    };

    int i = 0;
    while (i < text.length) {
      final ch = text[i];

      // ── 处理引号入栈/出栈 ───────────
      if (_openQuotes.containsKey(ch)) {
        // 对于左右同形的引号（ASCII " 和 '），用 toggle 逻辑
        final closesWith = _openQuotes[ch]!;
        if (ch == closesWith) {
          // 左右同形：栈空则入栈，栈顶相同则出栈
          if (quoteStack.isNotEmpty && quoteStack.last == ch) {
            quoteStack.removeLast();
          } else {
            quoteStack.add(ch);
          }
        } else {
          // 左右不同形的引号（"\u201C" → "\u201D"），直接入栈
          quoteStack.add(ch);
        }
        buffer.write(ch);
        i++;
        continue;
      }
      if (_closingQuoteSet.contains(ch)) {
        // 右引号 → 如果匹配栈顶则出栈
        if (quoteStack.isNotEmpty &&
            _openQuotes[quoteStack.last] == ch) {
          quoteStack.removeLast();
        }
        buffer.write(ch);
        i++;
        continue;
      }

      // ── 中文标点结尾（不在引号内才分割） ──
      if (ch == '\u3002' || ch == '\uFF1F' || ch == '\uFF01' || ch == '\uFF1B') {
        buffer.write(ch);
        // 吞掉后续的引号/括号（出栈）
        while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
          i++;
          final closeCh = text[i];
          if (quoteStack.isNotEmpty &&
              _openQuotes[quoteStack.last] == closeCh) {
            quoteStack.removeLast();
          }
          buffer.write(closeCh);
        }
        // 吞掉紧随的标注 [数字]（允许中间有空格）
        {
          int lookahead = i + 1;
          while (lookahead < text.length && (text[lookahead] == ' ' || text[lookahead] == '\t')) {
            lookahead++;
          }
          if (lookahead < text.length && text[lookahead] == '[') {
            int braceEnd = lookahead + 2;
            while (braceEnd < text.length && text[braceEnd] != ']') {
              braceEnd++;
            }
            if (braceEnd < text.length && text[braceEnd] == ']') {
              final inside = text.substring(lookahead + 2, braceEnd);
              if (inside.runes.every((r) => r >= 0x30 && r <= 0x39)) {
                // 写入中间的空格/制表符
                while (i + 1 < lookahead) {
                  i++;
                  buffer.write(text[i]);
                }
                // 写入 [数字]
                buffer.write('[');
                i++;
                while (i < braceEnd) {
                  i++;
                  buffer.write(text[i]);
                }
                // 吞掉后续的右引号
                while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
                  i++;
                  final closeCh = text[i];
                  if (quoteStack.isNotEmpty &&
                      _openQuotes[quoteStack.last] == closeCh) {
                    quoteStack.removeLast();
                  }
                  buffer.write(closeCh);
                }
              }
            }
          }
        }
        // 只在不在引号内时分割
        if (quoteStack.isEmpty) {
          _emitAndClear(buffer, result);
        }
        i++;
        continue;
      }

      // ── 英文问号/叹号结尾（不在引号内才分割） ──
      if (ch == '?' || ch == '!') {
        buffer.write(ch);
        while (i + 1 < text.length && (text[i + 1] == '?' || text[i + 1] == '!')) {
          i++;
          buffer.write(text[i]);
        }
        while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
          i++;
          final closeCh = text[i];
          if (quoteStack.isNotEmpty &&
              _openQuotes[quoteStack.last] == closeCh) {
            quoteStack.removeLast();
          }
          buffer.write(closeCh);
        }
        // 吞掉紧随的标注 [数字]（允许中间有空格）
        {
          int lookahead = i + 1;
          while (lookahead < text.length && (text[lookahead] == ' ' || text[lookahead] == '\t')) {
            lookahead++;
          }
          if (lookahead < text.length && text[lookahead] == '[') {
            int braceEnd = lookahead + 2;
            while (braceEnd < text.length && text[braceEnd] != ']') {
              braceEnd++;
            }
            if (braceEnd < text.length && text[braceEnd] == ']') {
              final inside = text.substring(lookahead + 2, braceEnd);
              if (inside.runes.every((r) => r >= 0x30 && r <= 0x39)) {
                // 写入中间的空格/制表符
                while (i + 1 < lookahead) {
                  i++;
                  buffer.write(text[i]);
                }
                // 写入 [数字]
                buffer.write('[');
                i++;
                while (i < braceEnd) {
                  i++;
                  buffer.write(text[i]);
                }
                // 吞掉后续的右引号
                while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
                  i++;
                  final closeCh = text[i];
                  if (quoteStack.isNotEmpty &&
                      _openQuotes[quoteStack.last] == closeCh) {
                    quoteStack.removeLast();
                  }
                  buffer.write(closeCh);
                }
              }
            }
          }
        }
        if (quoteStack.isEmpty) {
          _emitAndClear(buffer, result);
        }
        i++;
        continue;
      }

      // ── 英文句点结尾 ────────────
      if (ch == '.') {
        // 省略号
        if (i + 2 < text.length && text[i + 1] == '.' && text[i + 2] == '.') {
          while (i < text.length && text[i] == '.') {
            buffer.write(text[i]);
            i++;
          }
          continue;
        }
        // 数字小数点
        if (_isDigitBeforeDot(text, i) && _isDigitAfterDot(text, i)) {
          buffer.write(ch);
          i++;
          continue;
        }
        // 缩写
        final word = _extractWordBeforeDot(text, i);
        if (word.isNotEmpty && abbreviations.contains(word.toLowerCase())) {
          buffer.write(ch);
          i++;
          continue;
        }
        // 单字母缩写
        if (_isSingleLetterAbbreviation(text, i)) {
          buffer.write(ch);
          i++;
          continue;
        }
        // 真正句号
        buffer.write(ch);
        while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
          i++;
          final closeCh = text[i];
          if (quoteStack.isNotEmpty &&
              _openQuotes[quoteStack.last] == closeCh) {
            quoteStack.removeLast();
          }
          buffer.write(closeCh);
        }
        // 吞掉紧随的标注 [数字]（允许中间有空格）
        {
          int lookahead = i + 1;
          while (lookahead < text.length && (text[lookahead] == ' ' || text[lookahead] == '\t')) {
            lookahead++;
          }
          if (lookahead < text.length && text[lookahead] == '[') {
            int braceEnd = lookahead + 2;
            while (braceEnd < text.length && text[braceEnd] != ']') {
              braceEnd++;
            }
            if (braceEnd < text.length && text[braceEnd] == ']') {
              final inside = text.substring(lookahead + 2, braceEnd);
              if (inside.runes.every((r) => r >= 0x30 && r <= 0x39)) {
                // 写入中间的空格/制表符
                while (i + 1 < lookahead) {
                  i++;
                  buffer.write(text[i]);
                }
                // 写入 [数字]
                buffer.write('[');
                i++;
                while (i < braceEnd) {
                  i++;
                  buffer.write(text[i]);
                }
                // 吞掉后续的右引号
                while (i + 1 < text.length && _closingQuoteSet.contains(text[i + 1])) {
                  i++;
                  final closeCh = text[i];
                  if (quoteStack.isNotEmpty &&
                      _openQuotes[quoteStack.last] == closeCh) {
                    quoteStack.removeLast();
                  }
                  buffer.write(closeCh);
                }
              }
            }
          }
        }
        if (quoteStack.isEmpty) {
          _emitAndClear(buffer, result);
        }
        i++;
        continue;
      }

      // ── 省略号 …… ────────────
      if (ch == '\u2026' || ch == '\u2025') {
        while (i < text.length && (text[i] == '\u2026' || text[i] == '\u2025')) {
          buffer.write(text[i]);
          i++;
        }
        continue;
      }

      // ── 普通字符 ───────────────
      buffer.write(ch);
      i++;
    }

    // 剩余文本
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    return result.isEmpty ? [text] : result;
  }

  static bool _isDigitBeforeDot(String text, int i) {
    if (i <= 0) return false;
    return text.codeUnitAt(i - 1) >= 0x30 &&
           text.codeUnitAt(i - 1) <= 0x39;
  }

  static bool _isDigitAfterDot(String text, int i) {
    if (i + 1 >= text.length) return false;
    return text.codeUnitAt(i + 1) >= 0x30 &&
           text.codeUnitAt(i + 1) <= 0x39;
  }

  static String _extractWordBeforeDot(String text, int i) {
    if (i <= 0) return '';
    int start = i - 1;
    while (start >= 0) {
      final code = text.codeUnitAt(start);
      final isLetter = (code >= 0x41 && code <= 0x5A) ||
                       (code >= 0x61 && code <= 0x7A);
      if (!isLetter) break;
      start--;
    }
    start++;
    if (start >= i) return '';
    return text.substring(start, i);
  }

  static bool _isSingleLetterAbbreviation(String text, int i) {
    if (i <= 0) return false;
    final prev = text[i - 1];
    final code = prev.codeUnitAt(0);
    if (code < 0x41 || code > 0x5A) return false;
    return i + 1 >= text.length || text[i + 1] == ' ';
  }

  static void _emitAndClear(StringBuffer buffer, List<String> result) {
    final sentence = buffer.toString().trim();
    buffer.clear();
    if (sentence.isNotEmpty) {
      result.add(sentence);
    }
  }

  // ── 以下为原有辅助方法，未改动 ──

  static double estimateDisplayWidth(String text, double fontSize) {
    double width = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF) {
        width += fontSize;
      } else {
        width += fontSize * 0.5;
      }
    }
    return width;
  }

  static int countWords(String text) {
    if (text.isEmpty) return 0;
    int count = 0;
    bool inWord = false;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if ((code >= 0x4E00 && code <= 0x9FFF) ||
          (code >= 0x3040 && code <= 0x9FFF) ||
          (code >= 0xAC00 && code <= 0xD7AF)) {
        count++;
        inWord = false;
      } else if (RegExp(r'[a-zA-Z]').hasMatch(text[i])) {
        if (!inWord) {
          count++;
          inWord = true;
        }
      } else {
        inWord = false;
      }
    }
    return count;
  }

  static String generateId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }
}