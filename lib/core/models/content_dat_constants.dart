/// content.dat 二进制协议定义
///
/// ## 文件结构
/// ┌────────────────────────────────────────────┐
/// │ Magic (8 bytes): "BILXDATA"               │
/// │ Version (4 bytes, uint32)                  │
/// │ Chapter Count (Varint, 3B 槽)              │
/// │ Chapter Index Offset (Varint, 5B 槽)       │
/// │ Chapter Index Length (Varint, 3B 槽)       │
/// │ Reserved (1 byte)                          │
/// │ Total: 24 bytes header                     │
/// ├────────────────────────────────────────────┤
/// │ Content Data                                │
/// │  For each chapter:                         │
/// │    For each ContentBlock:                  │
/// │      Block Type (1 byte: 0=paragraph, 1=image)
/// │      ┌─ blockType = 0 (Paragraph)         │
/// │      │   Sentence Count (Varint)           │
/// │      │   For each sentence:                │
/// │      │     Global Index (Varint)           │
/// │      │     Text Length (Varint)            │
/// │      │     Text (UTF-8)                    │
/// │      └─────────────────────────────────── │
/// │      ┌─ blockType = 1 (Image)             │
/// │      │   Sentence Count = 0 (Varint)      │
/// │      │   Image Path: Varint(len) + UTF-8  │
/// │      │   Alt Text: Varint(len) + UTF-8    │
/// │      └─────────────────────────────────── │
/// ├────────────────────────────────────────────┤
/// │ Chapter Index (变长)                       │
/// │  对于每个章节：                             │
/// │    Chapter ID (Varint)                     │
/// │    Title Length (Varint)                   │
/// │    Title (UTF-8)                           │
/// │    Sentence Count (Varint)                 │
/// │    Content Offset (Varint)                 │
/// │    Content Length (Varint)                 │
/// └────────────────────────────────────────────┘
///
/// ## Header 字节偏移
/// ┌──────┬──────┬──────────────────┬──────────┐
/// │偏移   │大小  │字段              │编码       │
/// ├──────┼──────┼──────────────────┼──────────┤
/// │ 0    │ 8    │ Magic            │ UTF-8    │
/// │ 8    │ 4    │ Version          │ uint32 LE│
/// │ 12   │ 3    │ Chapter Count    │ Varint   │
/// │ 15   │ 5    │ Ch. Index Offset │ Varint   │
/// │ 20   │ 3    │ Ch. Index Length │ Varint   │
/// │ 23   │ 1    │ Reserved         │ 0x00     │
/// │      │ 24   │ 合计             │          │
/// └──────┴──────┴──────────────────┴──────────┘
class ContentDatConstants {
  ContentDatConstants._();

  static const String magic = 'BILXDATA';
  static const int currentVersion = 1;
  static const int headerSize = 24;

  // Header 中变长 Field 的固定槽位偏移和大小
  static const int offsetChapterCount = 12;
  static const int sizeChapterCountSlot = 3;

  static const int offsetChapterIndexOffset = 15;
  static const int sizeChapterIndexOffsetSlot = 5;

  static const int offsetChapterIndexLength = 20;
  static const int sizeChapterIndexLengthSlot = 3;

  static const int offsetReserved = 23;
  static const int sizeReserved = 1;

  // Block types
  static const int blockTypeParagraph = 0;
  static const int blockTypeImage = 1;
}