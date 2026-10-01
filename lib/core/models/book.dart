import 'chapter.dart';

/// Book 表示一本完整书籍
class Book {
  final String id;
  final String title;
  final String author;
  final String language;
  final String? cover;
  final int version;
  final List<Chapter> chapters;
  final List<TranslationMeta> translations;
  final Map<String, String> metadata;
  final DateTime? addedAt;
  final DateTime? updatedAt;
  final DateTime? lastReadAt;

  const Book({
    required this.id,
    required this.title,
    this.author = '',
    this.language = 'en',
    this.cover,
    this.version = 1,
    this.chapters = const [],
    this.translations = const [],
    this.metadata = const {},
    this.addedAt,
    this.updatedAt,
    this.lastReadAt,
  });

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? language,
    String? cover,
    int? version,
    List<Chapter>? chapters,
    List<TranslationMeta>? translations,
    Map<String, String>? metadata,
    DateTime? addedAt,
    DateTime? updatedAt,
    DateTime? lastReadAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      language: language ?? this.language,
      cover: cover ?? this.cover,
      version: version ?? this.version,
      chapters: chapters ?? this.chapters,
      translations: translations ?? this.translations,
      metadata: metadata ?? this.metadata,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'language': language,
        'cover': cover,
        'version': version,
        'translations': translations.map((t) => t.toJson()).toList(),
        'metadata': metadata,
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        language: json['language'] as String? ?? 'en',
        cover: json['cover'] as String?,
        version: json['version'] as int? ?? 1,
        translations: (json['translations'] as List<dynamic>?)
                ?.map((e) =>
                    TranslationMeta.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        metadata: (json['metadata'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
      );
}

/// TranslationMeta 描述一个翻译来源的元数据
class TranslationMeta {
  final int id;
  final String name;
  final String provider;
  final int sentenceCount;
  final DateTime? createdAt;

  const TranslationMeta({
    required this.id,
    required this.name,
    required this.provider,
    this.sentenceCount = 0,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'sentenceCount': sentenceCount,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory TranslationMeta.fromJson(Map<String, dynamic> json) =>
      TranslationMeta(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        sentenceCount: json['sentenceCount'] as int? ?? 0,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
      );
}