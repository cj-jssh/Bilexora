/// Sentence 是系统核心最小单位
///
/// 用于：
/// - 阅读
/// - 翻译
/// - 重新翻译
/// - 人工校对
/// - 单词交互
/// - TTS
/// - AI 解释
/// - 阅读统计
class Sentence {
  final int index;
  final String text;
  final String? language;
  final int charOffset;
  final int wordCount;

  const Sentence({
    required this.index,
    required this.text,
    this.language,
    this.charOffset = 0,
    this.wordCount = 0,
  });

  Sentence copyWith({
    int? index,
    String? text,
    String? language,
    int? charOffset,
    int? wordCount,
  }) {
    return Sentence(
      index: index ?? this.index,
      text: text ?? this.text,
      language: language ?? this.language,
      charOffset: charOffset ?? this.charOffset,
      wordCount: wordCount ?? this.wordCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        if (language != null) 'language': language,
        'charOffset': charOffset,
      };

  factory Sentence.fromJson(Map<String, dynamic> json) => Sentence(
        index: json['index'] as int,
        text: json['text'] as String? ?? '',
        language: json['language'] as String?,
        charOffset: json['charOffset'] as int? ?? 0,
      );
}