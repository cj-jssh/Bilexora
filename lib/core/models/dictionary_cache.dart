/// 词典查询缓存
class DictionaryCache {
  final String word;
  final String language;
  final String? translation;
  final String? definition;
  final String? phonetic;
  final String? partOfSpeech;
  final DateTime? cachedAt;

  const DictionaryCache({
    required this.word,
    required this.language,
    this.translation,
    this.definition,
    this.phonetic,
    this.partOfSpeech,
    this.cachedAt,
  });
}