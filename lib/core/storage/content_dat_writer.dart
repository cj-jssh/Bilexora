import 'dart:typed_data';
import 'dart:convert';
import '../models/models.dart';
import '../models/content_dat_constants.dart';

/// content.dat 文件写入器（Varint 压缩版）
class ContentDatWriter {
  final List<int> _buffer = [];
  int _offset = 0;

  ContentDatWriter(int maxSize);

  /// 写入完整内容数据
  Uint8List write(Book book) {
    _writeHeader(book);

    // ── 第一步：写入 Content Data ──────────
    final chaptersInfo = <_ChapterWriteInfo>[];

    for (int ci = 0; ci < book.chapters.length; ci++) {
      final chapter = book.chapters[ci];
      final start = _offset;
      for (final block in chapter.blocks) {
        block.when(
          paragraph: (paragraph) {
            _writeByte(ContentDatConstants.blockTypeParagraph);
            _writeVarint(paragraph.sentences.length);
            for (final sentence in paragraph.sentences) {
              _writeVarint(sentence.charOffset);
              _writeString(sentence.text);
            }
          },
          image: (imagePath, altText) {
            _writeByte(ContentDatConstants.blockTypeImage);
            _writeVarint(0);
            _writeString(imagePath);
            _writeString(altText ?? '');
          },
        );
      }
      chaptersInfo.add(_ChapterWriteInfo(
        chapterId: ci,
        title: chapter.title,
        sentenceCount: chapter.sentenceCount,
        contentOffset: start,
        contentLength: _offset - start,
      ));
    }

    // ── 第二步：写入 Chapter Index ────────
    final chapterIndexStart = _offset;
    for (final info in chaptersInfo) {
      _writeVarint(info.chapterId);
      _writeString(info.title); // writes Varint(len) + UTF-8
      _writeVarint(info.sentenceCount);
      _writeVarint(info.contentOffset);
      _writeVarint(info.contentLength);
    }
    final chapterIndexLength = _offset - chapterIndexStart;

    // ── 第三步：回填 Header ──
    _writeVarintAt(ContentDatConstants.offsetChapterCount,
                   ContentDatConstants.sizeChapterCountSlot,
                   book.chapters.length);
    _writeVarintAt(ContentDatConstants.offsetChapterIndexOffset,
                   ContentDatConstants.sizeChapterIndexOffsetSlot,
                   chapterIndexStart);
    _writeVarintAt(ContentDatConstants.offsetChapterIndexLength,
                   ContentDatConstants.sizeChapterIndexLengthSlot,
                   chapterIndexLength);

    return Uint8List.fromList(_buffer);
  }

  void _writeHeader(Book book) {
    _buffer.clear();
    _offset = 0;

    // 0-7: Magic (8 bytes)
    _writeFixedString(ContentDatConstants.magic, 8);
    // 8-11: Version (uint32)
    _writeUint32(ContentDatConstants.currentVersion);
    // 12-14: Chapter Count (Varint, 3B 槽) — 占位全填 0xFF
    for (int i = 0; i < ContentDatConstants.sizeChapterCountSlot; i++) {
      _writeByte(0xFF);
    }
    // 15-19: Chapter Index Offset (Varint, 5B 槽) — 占位全填 0xFF
    for (int i = 0; i < ContentDatConstants.sizeChapterIndexOffsetSlot; i++) {
      _writeByte(0xFF);
    }
    // 20-22: Chapter Index Length (Varint, 3B 槽) — 占位全填 0xFF
    for (int i = 0; i < ContentDatConstants.sizeChapterIndexLengthSlot; i++) {
      _writeByte(0xFF);
    }
    // 23: Reserved (1 byte)
    _writeByte(0);
  }

  /// 在已写入的 buffer 的固定位置 [offset] 写入 [value] 的 varint 编码，
  /// 最多占用 [maxSlotSize] 字节（不足高位补零）。
  void _writeVarintAt(int offset, int maxSlotSize, int value) {
    var v = value;
    for (int i = 0; i < maxSlotSize; i++) {
      if (v >= 0x80) {
        _buffer[offset + i] = (v & 0x7F) | 0x80;
        v >>= 7;
      } else {
        _buffer[offset + i] = v & 0x7F;
        // 剩余高位补 0
        for (int j = i + 1; j < maxSlotSize; j++) {
          _buffer[offset + j] = 0;
        }
        return;
      }
    }
    // value 超出槽位容量，截断（实际不可能，3B=2^21 够存 200万章，5B=2^35 够存 32GB）
  }

  void _writeUint32(int value) {
    _writeByte(value & 0xFF);
    _writeByte((value >> 8) & 0xFF);
    _writeByte((value >> 16) & 0xFF);
    _writeByte((value >> 24) & 0xFF);
  }

  void _writeVarint(int value) {
    var v = value;
    while (v >= 0x80) {
      _writeByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _writeByte(v & 0x7F);
  }

  void _writeString(String value) {
    final bytes = utf8.encode(value);
    _writeVarint(bytes.length);
    for (final b in bytes) { _writeByte(b); }
  }

  void _writeFixedString(String value, int fixedLength) {
    final bytes = utf8.encode(value);
    for (int i = 0; i < fixedLength; i++) {
      _writeByte(i < bytes.length ? bytes[i] : 0);
    }
  }

  void _writeByte(int byte) {
    _buffer.add(byte & 0xFF);
    _offset++;
  }
}

class _ChapterWriteInfo {
  final int chapterId;
  final String title;
  final int sentenceCount;
  final int contentOffset;
  final int contentLength;
  _ChapterWriteInfo({
    required this.chapterId,
    required this.title,
    required this.sentenceCount,
    required this.contentOffset,
    required this.contentLength,
  });
}