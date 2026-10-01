import 'dart:typed_data';
import 'dart:convert';
import '../models/models.dart';
import '../models/content_dat_constants.dart';

/// content.dat 文件读取器（Varint 压缩版）
class ContentDatReader {
  final Uint8List _data;
  int _readOffset = 0;
  int _chapterCount = 0;

  final List<_ChapterInfo> _chapterInfo = [];

  ContentDatReader(this._data) {
    _parseHeader();
  }

  void _parseHeader() {
    _readOffset = 0;

    // 0-7: Magic (8 bytes)
    final magic = utf8.decode(_data.sublist(_readOffset, _readOffset + 8));
    if (magic != ContentDatConstants.magic) {
      throw FormatException('Invalid content.dat magic: $magic');
    }
    _readOffset += 8;

    // 8-11: Version (uint32)
    _readUint32();

    // 12-14: Chapter Count (Varint, 3B 槽)
    _chapterCount = _readVarintSlot(ContentDatConstants.offsetChapterCount,
                                     ContentDatConstants.sizeChapterCountSlot);

    // 15-19: Chapter Index Offset (Varint, 5B 槽)
    final chapterIndexOffset = _readVarintSlot(
        ContentDatConstants.offsetChapterIndexOffset,
        ContentDatConstants.sizeChapterIndexOffsetSlot);

    // 20-22: Chapter Index Length (Varint, 3B 槽) — skip
    // 23: Reserved — skip
    _readOffset = ContentDatConstants.headerSize; // 24

    // Parse Chapter Index
    _readOffset = chapterIndexOffset;
    _parseChapterIndex();
  }

  /// 从当前 _readOffset 位置读取一个存储在固定槽中的 Varint。
  /// 槽最多 [slotSize] 字节，不足用 0 填充高位。
  int _readVarintSlot(int offset, int slotSize) {
    int result = 0;
    int shift = 0;
    for (int i = 0; i < slotSize; i++) {
      final byte = _data[offset + i];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break; // continuation flag = 0, 结束
      shift += 7;
    }
    return result;
  }

  void _parseChapterIndex() {
    for (int i = 0; i < _chapterCount; i++) {
      final chapterId = _readVarint();  // added Chapter ID
      final title = _readString();      // Varint(len) + UTF-8
      final sentenceCount = _readVarint();
      final contentOffset = _readVarint();
      final contentLength = _readVarint();
      _chapterInfo.add(_ChapterInfo(
        chapterId: chapterId,
        title: title,
        sentenceCount: sentenceCount,
        contentOffset: contentOffset,
        contentLength: contentLength,
      ));
    }
  }

  /// 获取章节数量
  int get chapterCount => _chapterCount;

  /// 读取指定章节的所有内容块
  Chapter? readChapter(int chapterIndex) {
    // 兼容两种查找方式：按 index 或者按 chapterId
    _ChapterInfo info;
    if (chapterIndex < _chapterInfo.length &&
        _chapterInfo[chapterIndex].chapterId == chapterIndex) {
      info = _chapterInfo[chapterIndex];
    } else {
      // 按 chapterId 查找
      final found = _chapterInfo.where((c) => c.chapterId == chapterIndex).toList();
      if (found.isEmpty) return null;
      info = found.first;
    }

    _readOffset = info.contentOffset;
    final endOffset = info.contentOffset + info.contentLength;

    final blocks = <ContentBlock>[];

    while (_readOffset < endOffset) {
      final blockType = _readUint8();

      if (blockType == ContentDatConstants.blockTypeParagraph) {
        final sentenceCount = _readVarint();
        final sentences = <Sentence>[];
        for (int i = 0; i < sentenceCount; i++) {
          final globalIndex = _readVarint();
          final text = _readString();
          sentences.add(Sentence(index: i, text: text, charOffset: globalIndex));
        }
        blocks.add(ContentBlock.paragraph(
          paragraph: Paragraph(index: blocks.length, sentences: sentences),
        ));
      } else if (blockType == ContentDatConstants.blockTypeImage) {
        _readVarint(); // sentence count = 0
        final imagePath = _readString();
        final altText = _readString();
        blocks.add(ContentBlock.image(
          imagePath: imagePath,
          altText: altText.isEmpty ? null : altText,
        ));
      }
    }

    return Chapter(
      index: info.chapterId,
      title: info.title,
      blocks: blocks,
      sentenceCount: info.sentenceCount,
      offset: info.contentOffset,
      length: info.contentLength,
    );
  }

  // ── 读取原语 ──────────────────────────────

  int _readUint8() => _data[_readOffset++];

  int _readUint32() {
    final v = ByteData.view(_data.buffer, _readOffset, 4).getUint32(0, Endian.little);
    _readOffset += 4;
    return v;
  }

  int _readVarint() {
    int result = 0;
    int shift = 0;
    while (true) {
      final byte = _data[_readOffset++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  String _readString() {
    final length = _readVarint();
    final str = utf8.decode(_data.sublist(_readOffset, _readOffset + length));
    _readOffset += length;
    return str;
  }
}

class _ChapterInfo {
  final int chapterId;
  final String title;
  final int sentenceCount;
  final int contentOffset;
  final int contentLength;
  _ChapterInfo({
    required this.chapterId,
    required this.title,
    required this.sentenceCount,
    required this.contentOffset,
    required this.contentLength,
  });
}