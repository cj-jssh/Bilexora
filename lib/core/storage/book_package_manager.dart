import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import 'content_dat_reader.dart';

/// Book Package 管理器
///
/// 负责单本书的存储、读取和写入。
///
/// 结构：
/// library/
/// ├── library.db
/// └── books/
///     ├── book_001/
///     │   ├── book.json
///     │   ├── content.dat
///     │   └── images/
///     │
///     └── book_002/
///         ├── book.json
///         ├── content.dat
///         └── images/
class BookPackageManager {
  final String _libraryPath;

  BookPackageManager(this._libraryPath);

  /// 获取书籍目录路径
  String _bookDirPath(String bookId) =>
      p.join(_libraryPath, 'books', bookId);

  /// 获取 book.json 路径
  String _bookJsonPath(String bookId) =>
      p.join(_bookDirPath(bookId), 'book.json');

  /// 获取 content.dat 路径
  String _contentDatPath(String bookId) =>
      p.join(_bookDirPath(bookId), 'content.dat');

  /// 获取图片目录路径
  String _imagesDirPath(String bookId) =>
      p.join(_bookDirPath(bookId), 'images');

  /// 创建 Book Package 目录结构
  Future<void> createBookPackage(Book book, Uint8List contentData) async {
    final dir = Directory(_bookDirPath(book.id));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 创建 images 目录
    final imagesDir = Directory(_imagesDirPath(book.id));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 写入 book.json
    final bookJson = jsonEncode(book.toJson());
    await File(_bookJsonPath(book.id)).writeAsString(bookJson);

    // 写入 content.dat
    await File(_contentDatPath(book.id)).writeAsBytes(contentData);
  }

  /// 读取 book.json 元数据
  Future<Book?> readBookMeta(String bookId) async {
    try {
      final file = File(_bookJsonPath(bookId));
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      return Book.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// 读取 content.dat
  Future<ContentDatReader?> openContentDat(String bookId) async {
    try {
      final file = File(_contentDatPath(bookId));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return ContentDatReader(bytes);
    } catch (e) {
      return null;
    }
  }

  /// 检查 Book Package 是否存在
  Future<bool> bookPackageExists(String bookId) async {
    final dir = Directory(_bookDirPath(bookId));
    return await dir.exists();
  }

  /// 删除 Book Package
  Future<void> deleteBookPackage(String bookId) async {
    final dir = Directory(_bookDirPath(bookId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 保存图片到 Book Package
  Future<void> saveImage(String bookId, String fileName, Uint8List data) async {
    final dir = Directory(_imagesDirPath(bookId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(p.join(_imagesDirPath(bookId), fileName)).writeAsBytes(data);
  }
}