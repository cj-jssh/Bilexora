/// 生词本词条
class VocabularyEntry {
  final String id;
  final String word;
  final String? translation;
  final String? definition;
  final String? exampleSentence;
  final String? bookId;
  final String? bookTitle;
  final int reviewCount;
  final bool isMastered;
  final DateTime? addedAt;
  final DateTime? lastReviewedAt;

  const VocabularyEntry({
    required this.id,
    required this.word,
    this.translation,
    this.definition,
    this.exampleSentence,
    this.bookId,
    this.bookTitle,
    this.reviewCount = 0,
    this.isMastered = false,
    this.addedAt,
    this.lastReviewedAt,
  });

  VocabularyEntry copyWith({
    String? id,
    String? word,
    String? translation,
    String? definition,
    String? exampleSentence,
    String? bookId,
    String? bookTitle,
    int? reviewCount,
    bool? isMastered,
    DateTime? addedAt,
    DateTime? lastReviewedAt,
  }) {
    return VocabularyEntry(
      id: id ?? this.id,
      word: word ?? this.word,
      translation: translation ?? this.translation,
      definition: definition ?? this.definition,
      exampleSentence: exampleSentence ?? this.exampleSentence,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      reviewCount: reviewCount ?? this.reviewCount,
      isMastered: isMastered ?? this.isMastered,
      addedAt: addedAt ?? this.addedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
    );
  }
}