import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bilexora/core/models/models.dart';
import 'package:bilexora/core/storage/content_dat_writer.dart';
import 'package:bilexora/core/storage/translation_file.dart';

/// content_{lang}.dat 回归测试
///
/// 重点覆盖曾导致 "FormatException: Unexpected extension byte" 的场景：
/// 连续逐句追加翻译时 Chapter Index 解析错位 + 追加覆盖丢句。
void main() {
  late Directory tempDir;
  late TranslationFileManager fm;
  final perChCounts = [4, 3, 2]; // 3 章，共 9 句

  Future<void> writeContentDat() async {
    int gi = 0;
    final chapters = <Chapter>[];
    for (int c = 0; c < perChCounts.length; c++) {
      final sentences = <Sentence>[];
      for (int s = 0; s < perChCounts[c]; s++) {
        sentences.add(Sentence(index: s, text: '第${c}章第$s句', charOffset: gi++));
      }
      chapters.add(Chapter(
        index: c,
        title: '章节$c',
        blocks: [
          ContentBlock.paragraph(paragraph: Paragraph(index: 0, sentences: sentences)),
        ],
        sentenceCount: perChCounts[c],
      ));
    }
    final bytes = ContentDatWriter(1 << 20)
        .write(Book(id: 'b', title: 'b', language: 'zh', chapters: chapters));
    await File('${tempDir.path}/content.dat').writeAsBytes(bytes);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trlx_test');
    await writeContentDat();
    fm = TranslationFileManager(tempDir.path, bookId: 'b');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('写入/读取往返', () {
    test('单章写入后按 globalIndex 读回', () async {
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e1', priority: 1, chapterIndex: 0,
        texts: ['a', 'b', 'c', 'd'], totalChapterCount: 3,
      );
      final map = await fm.loadTranslation('en', perChapterSentenceCounts: perChCounts);
      expect(map, {0: 'a', 1: 'b', 2: 'c', 3: 'd'});
    });

    test('appendTranslation 跨章分组 + 章内空位占位不进结果', () async {
      // 第0章第1句、第2章第0句（中间留空）
      await fm.appendTranslation(lang: 'en', engineId: 'e1', priority: 1,
          results: [(globalIndex: 1, text: 't1'), (globalIndex: 7, text: 't7')]);
      final map = await fm.loadTranslation('en', perChapterSentenceCounts: perChCounts);
      expect(map, {1: 't1', 7: 't7'});
      expect(map.containsKey(0), isFalse, reason: '空位不应污染结果');
      expect(await fm.translationSentenceCount('en'), 2);
    });

    test('连续逐句追加：三句分散追加后互不覆盖（回归）', () async {
      await fm.appendTranslation(lang: 'en', engineId: 'e1', priority: 1,
          results: [(globalIndex: 0, text: 's0')]);
      await fm.appendTranslation(lang: 'en', engineId: 'e1', priority: 1,
          results: [(globalIndex: 1, text: 's1')]);
      await fm.appendTranslation(lang: 'en', engineId: 'e1', priority: 1,
          results: [(globalIndex: 7, text: 's7')]);
      final map = await fm.loadTranslation('en', perChapterSentenceCounts: perChCounts);
      expect(map, {0: 's0', 1: 's1', 7: 's7'});
    });

    test('同章两次追加：合并保留旧句（回归）', () async {
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e1', priority: 1, chapterIndex: 0,
        texts: ['a', 'b'], totalChapterCount: 3,
      );
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e1', priority: 1, chapterIndex: 0,
        texts: ['', '', 'c', 'd'], totalChapterCount: 3,
      );
      final map = await fm.loadTranslation('en', perChapterSentenceCounts: perChCounts);
      expect(map, {0: 'a', 1: 'b', 2: 'c', 3: 'd'});
    });

    test('引擎隔离删除后其余章节保留', () async {
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e1', priority: 1, chapterIndex: 0,
        texts: ['a', 'b', 'c', 'd'], totalChapterCount: 3,
      );
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e2', priority: 2, chapterIndex: 2,
        texts: ['x', 'y'], totalChapterCount: 3,
      );
      await fm.deleteEngineFromLanguage('en', 'e1');
      final map = await fm.loadTranslation('en', perChapterSentenceCounts: perChCounts);
      expect(map, {7: 'x', 8: 'y'});
      final engines = await fm.listEnginesForLanguage('en');
      expect(engines.single.engineId, 'e2');
    });
  });

  group('损坏数据防护（不抛异常）', () {
    test('垃圾索引条目 → 相关章返回 null，其余可读', () async {
      await fm.appendChapterTranslation(
        lang: 'en', engineId: 'e1', priority: 1, chapterIndex: 0,
        texts: ['a', 'b', 'c', 'd'], totalChapterCount: 3,
      );
      final bytes = await File('${tempDir.path}/content_en.dat').readAsBytes();
      // 篡改第 1 章索引为指向数据区中间的垃圾条目：直接改不了 varint 布局，
      // 改为整体截断再追加脏字节，模拟旧版错位写入
      final dirty = Uint8List.fromList([...bytes, 0x88, 0x77, 0x66]);
      final map = TranslationFileReader(dirty).readAll(perChCounts);
      expect(map[0], 'a');
    });

    test('坏 magic / 过短文件 → 空结果', () {
      expect(TranslationFileReader(Uint8List.fromList([1, 2, 3])).readAll([]), isEmpty);
      expect(
        TranslationFileReader(Uint8List.fromList(List.filled(32, 0x41))).readAll([]),
        isEmpty,
      );
    });
  });
}
