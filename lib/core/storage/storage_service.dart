import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../database/library_database.dart';

/// 存储用量与缓存清理
class StorageService {
  StorageService();

  /// 递归统计目录总字节数
  static Future<int> _dirSize(Directory dir) async {
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        try {
          if (entity is File) {
            total += await entity.length();
          } else if (entity is Directory) {
            total += await _dirSize(entity);
          }
        } catch (_) {
          // 忽略单独失败的条目
        }
      }
    } catch (_) {
      // 目录不存在或无权限
    }
    return total;
  }

  /// 统计整个应用占用空间（字节）：
  /// 文档目录（library.db + books + 模型 + 外部词典）+ 缓存目录
  Future<(int, Map<String, int>)> appUsageBytes() async {
    final appDoc = await getApplicationDocumentsDirectory();
    final cacheDir = await getApplicationCacheDirectory();
    final tempDir = await getTemporaryDirectory();

    final docBytes = await _dirSize(appDoc);
    final cacheBytes = await _dirSize(cacheDir);
    final tempBytes = await _dirSize(tempDir);
    final total = docBytes + cacheBytes + tempBytes;

    return (total, {
      'documents': docBytes,
      'cache': cacheBytes,
      'temp': tempBytes,
    });
  }

  /// 清理可安全删除的缓存内容，返回释放的字节数。
  Future<int> clearCache() async {
    int released = 0;

    // 1. 系统临时目录
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        released += await _dirSize(tempDir);
        await _deleteContents(tempDir);
      }
    } catch (_) {}

    // 2. 系统缓存目录
    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists()) {
        released += await _dirSize(cacheDir);
        await _deleteContents(cacheDir);
      }
    } catch (_) {}

    // 3. 词典缓存表（可重建的查词缓存）
    try {
      final db = LibraryDatabase();
      final before = await getCacheEntryBytes();
      await db.clearDictionaryCache();
      final after = await getCacheEntryBytes();
      released += (before - after).clamp(0, before);
    } catch (_) {}

    return released;
  }

  /// 清空目录下的所有条目（保留目录本身）
  static Future<void> _deleteContents(Directory dir) async {
    await for (final entity in dir.list(followLinks: false)) {
      try {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else {
          await entity.delete();
        }
      } catch (_) {}
    }
  }

  /// 估算词典缓存占用的字节数（仅用于展示，近似值）
  Future<int> getCacheEntryBytes() async {
    try {
      final db = LibraryDatabase();
      return await db.getDictionaryCacheEstimate();
    } catch (_) {
      return 0;
    }
  }
}

/// 格式化字节数为可读文本
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}