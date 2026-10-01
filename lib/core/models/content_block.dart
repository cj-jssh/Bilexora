import 'paragraph.dart';

/// ContentBlock 表示内容顺序和内容类型
class ContentBlock {
  final String blockType; // 'paragraph' or 'image'

  // For paragraph type
  final Paragraph? paragraph;

  // For image type
  final String? imagePath;
  final String? altText;

  const ContentBlock._({
    required this.blockType,
    this.paragraph,
    this.imagePath,
    this.altText,
  });

  /// 创建段落块
  factory ContentBlock.paragraph({required Paragraph paragraph}) =>
      ContentBlock._(
        blockType: 'paragraph',
        paragraph: paragraph,
      );

  /// 创建图片块
  factory ContentBlock.image({required String imagePath, String? altText}) =>
      ContentBlock._(
        blockType: 'image',
        imagePath: imagePath,
        altText: altText,
      );

  /// 根据类型执行不同操作
  T when<T>({
    required T Function(Paragraph paragraph) paragraph,
    required T Function(String imagePath, String? altText) image,
  }) {
    switch (blockType) {
      case 'paragraph':
        return paragraph(this.paragraph!);
      case 'image':
        return image(imagePath!, altText);
      default:
        throw StateError('Unknown block type: $blockType');
    }
  }

  String get typeName => blockType;

  Map<String, dynamic> toJson() => {
        'blockType': blockType,
        if (paragraph != null) 'paragraph': paragraph!.toJson(),
        if (imagePath != null) 'imagePath': imagePath,
        if (altText != null) 'altText': altText,
      };

  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    final type = json['blockType'] as String;
    switch (type) {
      case 'paragraph':
        return ContentBlock.paragraph(
          paragraph: Paragraph.fromJson(
              json['paragraph'] as Map<String, dynamic>),
        );
      case 'image':
        return ContentBlock.image(
          imagePath: json['imagePath'] as String,
          altText: json['altText'] as String?,
        );
      default:
        throw FormatException('Unknown block type: $type');
    }
  }
}