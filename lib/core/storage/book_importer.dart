import 'dart:io';
import 'dart:convert';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import '../../core/storage/book_package_manager.dart';
import '../../core/storage/content_dat_writer.dart';
import '../../core/utils/text_utils.dart';

/// EPUB / TXT 文件导入器
///
/// 负责：
/// 1. 解析原始 EPUB / TXT
/// 2. 标准化为 Book 模型
/// 3. 写入 Book Package
class BookImporter {
  final BookPackageManager _packageManager;
  final Uuid _uuid = const Uuid();

  BookImporter(this._packageManager);

  /// 导入 EPUB 文件
  Future<Book> importEpub(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('EPUB file not found', filePath);
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 解析 OPF 文件获取元数据
    final opfFile = _findOpfFile(archive);
    final opfXml = XmlDocument.parse(
        utf8.decode(archive.findFile(opfFile)!.content as List<int>));

    // OPF 文件所在目录（用于解析相对路径）
    final opfDir = p.dirname(opfFile);

    final book = await _parseEpubMeta(opfXml, archive);

    // 解析章节内容
    final chapters = await _parseEpubChapters(archive, opfXml, opfDir);
    final bookWithChapters = book.copyWith(chapters: chapters);

    // 提取并保存封面图片
    String? coverPath = await _extractCover(archive, opfXml, book.id, opfDir);

    final finalBook = bookWithChapters.copyWith(cover: coverPath);

    // 生成 content.dat
    final writer = ContentDatWriter(1024 * 1024 * 10); // 10MB max
    final contentData = writer.write(finalBook);

    // 保存 Book Package
    await _packageManager.createBookPackage(finalBook, contentData);

    // 保存图片
    await _saveImages(archive, book.id);

    return finalBook;
  }

  /// 导入 TXT 文件
  Future<Book> importTxt(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('TXT file not found', filePath);
    }

    final bookId = 'book_${_uuid.v4().substring(0, 8)}';
    final content = await file.readAsString(encoding: utf8);
    final lines = content.split('\n');

    // 尝试提取标题（第一行或文件名）
    String title = p.basenameWithoutExtension(filePath);
    String author = '';

    final chapters = <Chapter>[];
    final sentences = <Sentence>[];
    int globalIndex = 0;

    // 简单分段：空行作为段落分隔
    final paragraphs = <String>[];
    String currentParagraph = '';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty && currentParagraph.isNotEmpty) {
        paragraphs.add(currentParagraph);
        currentParagraph = '';
      } else if (trimmed.isNotEmpty) {
        currentParagraph += (currentParagraph.isEmpty ? '' : ' ') + trimmed;
      }
    }
    if (currentParagraph.isNotEmpty) {
      paragraphs.add(currentParagraph);
    }

    final blockSentences = <Sentence>[];
    for (int i = 0; i < paragraphs.length; i++) {
      // 将段落拆分为句子（简单按标点分割）
      final paraSentences = TextUtils.splitSentences(paragraphs[i]);
      for (final s in paraSentences) {
        sentences.add(Sentence(
          index: sentences.length,
          text: s,
          charOffset: globalIndex,
        ));
        blockSentences.add(Sentence(
          index: blockSentences.length,
          text: s,
          charOffset: globalIndex,
        ));
        globalIndex++;
      }
    }

    final chapter = Chapter(
      index: 0,
      title: title,
      blocks: [
        ContentBlock.paragraph(
          paragraph: Paragraph(
            index: 0,
            sentences: blockSentences,
          ),
        ),
      ],
      sentenceCount: sentences.length,
    );
    chapters.add(chapter);

    final book = Book(
      id: bookId,
      title: title,
      author: author,
      language: 'unknown',
      chapters: chapters,
    );

    // 生成 content.dat
    final writer = ContentDatWriter(1024 * 1024 * 10);
    final contentData = writer.write(book);

    await _packageManager.createBookPackage(book, contentData);

    return book;
  }

  // ========================
  // EPUB 解析辅助方法
  // ========================

  String _findOpfFile(Archive archive) {
    // 查找 container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw FormatException('Invalid EPUB: missing META-INF/container.xml');
    }

    final containerXml = XmlDocument.parse(
        utf8.decode(containerFile.content as List<int>));
    final rootfile = containerXml.findAllElements('rootfile').first;
    return rootfile.getAttribute('full-path')!;
  }

  Future<Book> _parseEpubMeta(XmlDocument opfXml, Archive archive) async {
    final bookId = 'book_${_uuid.v4().substring(0, 8)}';

    // 尝试从 OPF 文件中提取元数据
    String title = '';
    String author = '';
    String language = 'en';

    final metadata = opfXml.findAllElements('metadata').firstOrNull;
    if (metadata != null) {
      // EPUB 使用 dc: 命名空间，需通过 localName 匹配标签
      title = _dcText(metadata, 'title');
      author = _dcText(metadata, 'creator');
      final langText = _dcText(metadata, 'language');
      if (langText.isNotEmpty) language = langText;
    }

    return Book(
      id: bookId,
      title: title.isNotEmpty ? title : 'Unknown Title',
      author: author,
      language: language,
    );
  }

  /// 在 metadata 中按标签 localName 查找文本（忽略命名空间前缀）
  String _dcText(XmlElement parent, String localTag) {
    for (final child in parent.children) {
      if (child is XmlElement && child.name.local == localTag) {
        return child.innerText.trim();
      }
    }
    return '';
  }

  Future<List<Chapter>> _parseEpubChapters(
      Archive archive, XmlDocument opfXml, String opfDir) async {
    final chapters = <Chapter>[];
    final manifest = opfXml.findAllElements('manifest').firstOrNull;
    final spine = opfXml.findAllElements('spine').firstOrNull;

    if (manifest == null || spine == null) {
      // Fallback: 只有一个章节包含所有内容
      return _parseFallbackChapter(archive);
    }

    // 构建 ID 到 href 的映射
    final idToHref = <String, String>{};
    for (final item in manifest.findElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) {
        idToHref[id] = href;
      }
    }

    int globalIndex = 0;
    for (final itemref in spine.findElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref == null) continue;

      final href = _resolveHref(idToHref[idref]!, opfDir);
      if (href.isEmpty) continue;

      final xhtmlFile = archive.findFile(href);
      if (xhtmlFile == null) continue;

      final xhtmlContent = utf8.decode(xhtmlFile.content as List<int>);
      final xhtmlDoc = XmlDocument.parse(xhtmlContent);

      // 提取标题
      String chapterTitle = 'Chapter ${chapters.length + 1}';
      final titleElem = xhtmlDoc.findAllElements('title').firstOrNull;
      if (titleElem != null) chapterTitle = titleElem.innerText;

      // 提取段落
      final blocks = <ContentBlock>[];
      final body = xhtmlDoc.findAllElements('body').firstOrNull;
      if (body != null) {
        // 图片路径基于 xhtml 文件所在目录
        final xhtmlDir = p.dirname(href);
        for (final elem in body.descendants) {
          if (elem is XmlElement && elem.localName == 'p') {
            final text = elem.innerText.trim();
            if (text.isEmpty) continue;

            final sentences = TextUtils.splitSentences(text);
            final sentenceList = <Sentence>[];
            for (final s in sentences) {
              sentenceList.add(Sentence(
                index: sentenceList.length,
                text: s,
                charOffset: globalIndex,
              ));
              globalIndex++;
            }

            blocks.add(ContentBlock.paragraph(
              paragraph: Paragraph(
                index: blocks.length,
                sentences: sentenceList,
              ),
            ));
          } else if (elem is XmlElement && elem.localName == 'img') {
            final src = elem.getAttribute('src');
            if (src != null) {
              // 解析相对于 xhtml 文件路径
              final resolvedPath = p.isAbsolute(src)
                  ? src
                  : p.normalize(p.join(xhtmlDir, src));
              blocks.add(ContentBlock.image(imagePath: resolvedPath));
            }
          }
        }
      }

      if (blocks.isNotEmpty) {
        chapters.add(Chapter(
          index: chapters.length,
          title: chapterTitle,
          blocks: blocks,
          sentenceCount: blocks
              .where((b) => b.blockType == 'paragraph')
              .fold(0, (sum, b) => sum + (b.paragraph?.sentences.length ?? 0)),
        ));
      }
    }

    // 如果没有解析到章节，使用 fallback
    if (chapters.isEmpty) {
      return _parseFallbackChapter(archive);
    }

    return chapters;
  }

  Future<List<Chapter>> _parseFallbackChapter(Archive archive) async {
    final blocks = <ContentBlock>[];
    int globalIndex = 0;

    for (final file in archive.files) {
      if (file.name.endsWith('.xhtml') ||
          file.name.endsWith('.html') ||
          file.name.endsWith('.htm')) {
        try {
          final content = utf8.decode(file.content as List<int>);
          final doc = XmlDocument.parse(content);
          final body = doc.findAllElements('body').firstOrNull;
          if (body == null) continue;

          for (final elem in body.descendants) {
            if (elem is XmlElement && elem.localName == 'p') {
              final text = elem.innerText.trim();
              if (text.isEmpty) continue;

              final sentences = TextUtils.splitSentences(text);
              final sentenceList = <Sentence>[];
              for (final s in sentences) {
                sentenceList.add(Sentence(
                  index: sentenceList.length,
                  text: s,
                  charOffset: globalIndex,
                ));
                globalIndex++;
              }

              blocks.add(ContentBlock.paragraph(
                paragraph: Paragraph(
                  index: blocks.length,
                  sentences: sentenceList,
                ),
              ));
            }
          }
        } catch (_) {
          // Skip files that can't be parsed
        }
      }
    }

    return [
      Chapter(
        index: 0,
        title: 'Content',
        blocks: blocks,
        sentenceCount: globalIndex,
      ),
    ];
  }

  Future<String?> _extractCover(
      Archive archive, XmlDocument opfXml, String bookId, String opfDir) async {
    // 尝试从 OPF metadata 中获取 cover
    final metadata = opfXml.findAllElements('metadata').firstOrNull;
    if (metadata != null) {
      for (final meta in metadata.findElements('meta')) {
        final name = meta.getAttribute('name');
        final content = meta.getAttribute('content');
        if (name == 'cover' && content != null) {
          // 找到 cover 图片 ID → manifest 中查找 href
          final manifest = opfXml.findAllElements('manifest').firstOrNull;
          if (manifest != null) {
            for (final item in manifest.findElements('item')) {
              if (item.getAttribute('id') == content) {
                final href = item.getAttribute('href');
                if (href != null) {
                  // 将 href 解析为相对于 OPF 目录的路径
                  final resolvedHref = opfDir.isEmpty ? href : p.normalize(p.join(opfDir, href));
                  final coverFile = archive.findFile(resolvedHref);
                  if (coverFile != null) {
                    final ext = p.extension(href);
                    final coverName = 'cover$ext';
                    await _packageManager.saveImage(
                        bookId, coverName,
                        coverFile.content);
                    return coverName;
                  }
                }
              }
            }
          }
        }
      }

      // 备选方案：有些 EPUB 使用 <meta name="cover" content="cover-image"/> 且 content 直接是 href
      // 或者在 manifest 中有 properties="cover-image" 的 item
      final manifest = opfXml.findAllElements('manifest').firstOrNull;
      if (manifest != null) {
        for (final item in manifest.findElements('item')) {
          final props = item.getAttribute('properties');
          if (props != null && props.contains('cover-image')) {
            final href = item.getAttribute('href');
            if (href != null) {
              final resolvedHref = opfDir.isEmpty ? href : p.normalize(p.join(opfDir, href));
              final coverFile = archive.findFile(resolvedHref);
              if (coverFile != null) {
                final ext = p.extension(href);
                final coverName = 'cover$ext';
                await _packageManager.saveImage(
                    bookId, coverName,
                    coverFile.content);
                return coverName;
              }
            }
          }
        }
      }
    }
    return null;
  }

  Future<void> _saveImages(Archive archive, String bookId) async {
    for (final file in archive.files) {
      if (file.name.endsWith('.jpg') ||
          file.name.endsWith('.jpeg') ||
          file.name.endsWith('.png') ||
          file.name.endsWith('.gif') ||
          file.name.endsWith('.webp')) {
        final fileName = p.basename(file.name);
        await _packageManager.saveImage(
            bookId, fileName, file.content);
      }
    }
  }

  /// 解析 href，使其相对于 OPF 目录
  String _resolveHref(String href, String opfDir) {
    if (opfDir.isEmpty) return href;
    return p.normalize(p.join(opfDir, href));
  }
}