/// 阅读进度
class ReadingProgress {
  final String bookId;
  final int chapter;
  final int paragraph;
  final int sentence;
  final int charOffset;
  final double percentage;
  final DateTime? updatedAt;

  const ReadingProgress({
    required this.bookId,
    this.chapter = 0,
    this.paragraph = 0,
    this.sentence = 0,
    this.charOffset = 0,
    this.percentage = 0.0,
    this.updatedAt,
  });

  ReadingProgress copyWith({
    String? bookId,
    int? chapter,
    int? paragraph,
    int? sentence,
    int? charOffset,
    double? percentage,
    DateTime? updatedAt,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      paragraph: paragraph ?? this.paragraph,
      sentence: sentence ?? this.sentence,
      charOffset: charOffset ?? this.charOffset,
      percentage: percentage ?? this.percentage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'chapter': chapter,
        'paragraph': paragraph,
        'sentence': sentence,
        'char_offset': charOffset,
        'percentage': percentage,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        bookId: json['book_id'] as String,
        chapter: json['chapter'] as int? ?? 0,
        paragraph: json['paragraph'] as int? ?? 0,
        sentence: json['sentence'] as int? ?? 0,
        charOffset: json['char_offset'] as int? ?? 0,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
        updatedAt: json['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int)
            : null,
      );
}