import 'sentence.dart';

/// Paragraph 是内容结构单位
///
/// 作用：
/// - 表示段落边界
/// - 控制 Reader 的段落间距
/// - 作为整段翻译的操作范围
///
/// 不保存具体排版数据。
class Paragraph {
  final int index;
  final List<Sentence> sentences;

  const Paragraph({
    required this.index,
    this.sentences = const [],
  });

  Paragraph copyWith({
    int? index,
    List<Sentence>? sentences,
  }) {
    return Paragraph(
      index: index ?? this.index,
      sentences: sentences ?? this.sentences,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'sentences': sentences.map((s) => s.toJson()).toList(),
      };

  factory Paragraph.fromJson(Map<String, dynamic> json) => Paragraph(
        index: json['index'] as int,
        sentences: (json['sentences'] as List<dynamic>?)
                ?.map(
                    (e) => Sentence.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}