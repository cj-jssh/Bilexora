import 'package:flutter_test/flutter_test.dart';

import 'package:bilexora/core/models/models.dart';
import 'package:bilexora/core/storage/content_dat_writer.dart';
import 'package:bilexora/core/storage/content_dat_reader.dart';

/// 实证验证：content.dat 字节级往返（写入 → 读取）后句子数据是否完整有序
///
/// 背景：怀疑"传给 Bergamot 的批量句子是乱的"。
/// 本测试模拟 book_importer 的写入路径 + library_screen._doBatchTranslate
/// 的读取路径，逐项校验 globalIndex 与文本内容。
void main() {
  group('content.dat 字节级往返完整性', () {
    test('多章节多段落多句：globalIndex 连续且与文本一一对应', () {
      // ── 1. 构造与 book_importer 一致的 Book（模拟导入） ──
      final chapters = <Chapter>[];
      int gi = 0;
      final expected = <int, String>{}; // globalIndex → text

      for (int c = 0; c < 3; c++) {
        final blocks = <ContentBlock>[];
        for (int b = 0; b < 2; b++) {
          final sentences = <Sentence>[];
          for (int s = 0; s < 3; s++) {
            final text = '章节$c-段落$b-句子$s。这是唯一内容:$gi';
            sentences.add(Sentence(index: s, text: text, charOffset: gi));
            expected[gi] = text;
            gi++;
          }
          blocks.add(ContentBlock.paragraph(
            paragraph: Paragraph(index: b, sentences: sentences),
          ));
        }
        chapters.add(Chapter(
          index: c,
          title: '第${c + 1}章 标题测试',
          blocks: blocks,
          sentenceCount: 6,
        ));
      }
      final book = Book(
        id: 'test_book',
        title: '往返测试',
        language: 'zh',
        chapters: chapters,
      );

      // ── 2. 写入 content.dat 字节流 ──
      final writer = ContentDatWriter(10 * 1024 * 1024);
      final bytes = writer.write(book);

      // ── 3. 按读取方 (_doBatchTranslate) 的方式解析 ──
      final reader = ContentDatReader(bytes);
      final allSentences = <({int globalIndex, String text})>{};

      for (int i = 0; i < reader.chapterCount; i++) {
        final ch = reader.readChapter(i);
        if (ch == null) continue;
        for (final block in ch.blocks) {
          block.when(
            paragraph: (p) {
              for (final s in p.sentences) {
                allSentences.add((globalIndex: s.charOffset, text: s.text));
                // ⚠️ 注意：_doBatchTranslate 用的是 Record 集合，逐句校验
                expect(s.charOffset, expected.entries
                    .firstWhere((e) => e.value == s.text, orElse: () => const MapEntry(-999, ''))
                    .key,
                    reason: '文本 "${s.text}" 的 globalIndex 错位');
              }
            },
            image: (_, _) {},
          );
        }
      }

      // ── 4. 校验集合完整性与顺序 ──
      expect(allSentences.length, 18, reason: '总句数应为 18');
      final indices = allSentences.map((s) => s.globalIndex).toList()..sort();
      expect(indices, List.generate(18, (i) => i), reason: 'globalIndex 应为 0..17 连续');

      // 每句文本与 globalIndex 对应关系一致（无错位/丢失）
      for (final entry in expected.entries) {
        final found = allSentences.where((s) => s.globalIndex == entry.key).toList();
        expect(found.length, 1, reason: 'globalIndex ${entry.key} 应恰好出现一次');
        expect(found.first.text, entry.value,
            reason: 'globalIndex ${entry.key} 的文本不匹配');
      }

      // ── 5. 验证 Header 回填正确 ──
      // 从固定偏移读取 Varint 槽：Chapter Index Offset 在 offset=15，5 字节槽
      int readVarintSlot(int offset, int slotSize) {
        int result = 0, shift = 0;
        for (int i = 0; i < slotSize; i++) {
          final byte = bytes[offset + i];
          result |= (byte & 0x7F) << shift;
          if ((byte & 0x80) == 0) break;
          shift += 7;
        }
        return result;
      }
      final chIdxOff = readVarintSlot(15, 5);
      final chIdxLen = readVarintSlot(20, 3);
      expect(chIdxOff, greaterThan(24),
          reason: 'Chapter Index Offset 应被回填为有效位置');
      expect(chIdxLen, greaterThan(0),
          reason: 'Chapter Index Length 应被回填为正数');
    });

    test('Varint 大数值边界：>2^21 的 globalIndex 仍正确', () {
      final chapter = Chapter(
        index: 0,
        title: '边界',
        blocks: [
          ContentBlock.paragraph(
            paragraph: Paragraph(index: 0, sentences: [
              Sentence(index: 0, text: '边界句子A', charOffset: 2097151), // 2^21-1
              Sentence(index: 1, text: '边界句子B', charOffset: 2097152), // 2^21
              Sentence(index: 2, text: '边界句子C', charOffset: 33554431), // 2^25-1
            ]),
          ),
        ],
        sentenceCount: 3,
      );
      final book = Book(id: 't', title: 't', chapters: [chapter]);
      final bytes = ContentDatWriter(1 << 20).write(book);
      final reader = ContentDatReader(bytes);
      final ch = reader.readChapter(0)!;
      expect(ch.blocks.first.paragraph!.sentences.map((s) => s.charOffset).toList(),
          [2097151, 2097152, 33554431]);
    });

    test('含图片块时段落句子不串位', () {
      final sentences = <Sentence>[];
      final expected = <int, String>{};
      for (int i = 0; i < 2; i++) {
        final text = '图前句子$i=$i';
        sentences.add(Sentence(index: i, text: text, charOffset: i));
        expected[i] = text;
      }
      final chapter = Chapter(
        index: 0,
        title: '图文',
        blocks: [
          ContentBlock.paragraph(
              paragraph: Paragraph(index: 0, sentences: sentences)),
          ContentBlock.image(imagePath: 'images/pic.png', altText: '图片'),
          ContentBlock.paragraph(
              paragraph: Paragraph(index: 1, sentences: [
            Sentence(index: 0, text: '图后句子', charOffset: 2),
          ])),
        ],
        sentenceCount: 3,
      );
      final book = Book(id: 't', title: 't', chapters: [chapter]);
      final bytes = ContentDatWriter(1 << 20).write(book);
      final reader = ContentDatReader(bytes);
      final ch = reader.readChapter(0)!;

      final got = <int, String>{};
      for (final b in ch.blocks) {
        b.when(
          paragraph: (p) {
            for (final s in p.sentences) {
              got[s.charOffset] = s.text;
            }
          },
          image: (_, _) {},
        );
      }
      expect(got, {0: '图前句子0=0', 1: '图前句子1=1', 2: '图后句子'});
    });
  });
}
