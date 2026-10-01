import 'content_block.dart';

/// Chapter 章节单位
///
/// 同时是主要的：
/// - 磁盘 I/O 单位
/// - RAM Cache 单位
/// - 阅读加载单位
class Chapter {
  final int index;
  final String title;
  final List<ContentBlock> blocks;
  final int sentenceCount;
  final int offset;
  final int length;

  const Chapter({
    required this.index,
    this.title = '',
    this.blocks = const [],
    this.sentenceCount = 0,
    this.offset = 0,
    this.length = 0,
  });

  Chapter copyWith({
    int? index,
    String? title,
    List<ContentBlock>? blocks,
    int? sentenceCount,
    int? offset,
    int? length,
  }) {
    return Chapter(
      index: index ?? this.index,
      title: title ?? this.title,
      blocks: blocks ?? this.blocks,
      sentenceCount: sentenceCount ?? this.sentenceCount,
      offset: offset ?? this.offset,
      length: length ?? this.length,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'sentenceCount': sentenceCount,
      };

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        index: json['index'] as int,
        title: json['title'] as String? ?? '',
        blocks: (json['blocks'] as List<dynamic>?)
                ?.map(
                    (e) => ContentBlock.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        sentenceCount: json['sentenceCount'] as int? ?? 0,
      );
}