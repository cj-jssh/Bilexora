import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

/// LibraryDatabase 管理 library.db
///
/// 负责：
/// - 书库索引 (books 表)
/// - 阅读进度 (reading_progress 表)
/// - 生词本 (vocabulary 表)
/// - 词典缓存 (dictionary_cache 表)
/// - 应用设置 (settings 表)
class LibraryDatabase {
  static Database? _database;

  /// 打开/创建 library.db
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'library.db');

    return await openDatabase(
      dbPath,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // books 表 - 书库索引
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL DEFAULT 'en',
        cover TEXT,
        path TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_read_at INTEGER
      )
    ''');

    // reading_progress 表 - 阅读进度
    await db.execute('''
      CREATE TABLE reading_progress (
        book_id TEXT PRIMARY KEY,
        chapter INTEGER NOT NULL DEFAULT 0,
        paragraph INTEGER NOT NULL DEFAULT 0,
        sentence INTEGER NOT NULL DEFAULT 0,
        char_offset INTEGER NOT NULL DEFAULT 0,
        percentage REAL NOT NULL DEFAULT 0.0,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id)
      )
    ''');

    // vocabulary 表 - 生词本
    await db.execute('''
      CREATE TABLE vocabulary (
        id TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        translation TEXT,
        definition TEXT,
        example_sentence TEXT,
        book_id TEXT,
        book_title TEXT,
        review_count INTEGER NOT NULL DEFAULT 0,
        is_mastered INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        last_reviewed_at INTEGER
      )
    ''');

    // dictionary_cache 表 - 词典缓存
    await db.execute('''
      CREATE TABLE dictionary_cache (
        word TEXT NOT NULL,
        language TEXT NOT NULL,
        translation TEXT,
        definition TEXT,
        phonetic TEXT,
        part_of_speech TEXT,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (word, language)
      )
    ''');

    // settings 表 - 应用设置
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // v2: reading_time 表 - 每日阅读时长
    await _createReadingTimeTable(db);
    // v3: notifications 表 - 通知
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        book_id TEXT,
        read INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    // v4: translation_status 表 - 翻译状态
    await db.execute('''
      CREATE TABLE IF NOT EXISTS translation_status (
        book_id TEXT NOT NULL,
        language TEXT NOT NULL,
        book_title TEXT NOT NULL DEFAULT '',
        sentence_count INTEGER NOT NULL DEFAULT 0,
        engine_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'completed',
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (book_id, language)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createReadingTimeTable(db);
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          book_id TEXT,
          read INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS translation_status (
          book_id TEXT NOT NULL,
          language TEXT NOT NULL,
          book_title TEXT NOT NULL DEFAULT '',
          sentence_count INTEGER NOT NULL DEFAULT 0,
          engine_id TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'completed',
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (book_id, language)
        )
      ''');
    }
  }

  Future<void> _createReadingTimeTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reading_time (
        book_id TEXT NOT NULL,
        date TEXT NOT NULL,
        seconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (book_id, date)
      )
    ''');
  }

  // ========================
  // Books CRUD
  // ========================

  /// 获取所有书籍
  Future<List<Book>> getAllBooks() async {
    final db = await database;
    final maps = await db.query('books', orderBy: 'updated_at DESC');
    return maps.map((map) => _bookFromMap(map)).toList();
  }

  /// 根据 ID 获取单本书
  Future<Book?> getBook(String id) async {
    final db = await database;
    final maps = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return _bookFromMap(maps.first);
  }

  /// 插入/更新书籍
  Future<void> upsertBook(Book book) async {
    final db = await database;
    await db.insert(
      'books',
      _bookToMap(book),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除书籍
  Future<void> deleteBook(String id) async {
    final db = await database;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  /// 搜索书籍
  Future<List<Book>> searchBooks(String query) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'title LIKE ? OR author LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => _bookFromMap(map)).toList();
  }

  /// 获取最近阅读的书籍（last_read_at 不为空，按时间倒序）
  Future<Book?> getLastReadBook() async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'last_read_at IS NOT NULL',
      orderBy: 'last_read_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _bookFromMap(maps.first);
  }

  /// 获取最近阅读的多本书
  Future<List<Book>> getRecentBooks({int limit = 3}) async {
    final db = await database;
    final maps = await db.query(
      'books',
      where: 'last_read_at IS NOT NULL',
      orderBy: 'last_read_at DESC',
      limit: limit,
    );
    return maps.map((map) => _bookFromMap(map)).toList();
  }

  // ========================
  // Reading Progress
  // ========================

  /// 获取阅读进度
  Future<ReadingProgress?> getProgress(String bookId) async {
    final db = await database;
    final maps = await db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (maps.isEmpty) return null;
    return _progressFromMap(maps.first);
  }

  /// 保存阅读进度
  Future<void> saveProgress(ReadingProgress progress) async {
    final db = await database;
    await db.insert(
      'reading_progress',
      _progressToMap(progress),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ========================
  // Vocabulary
  // ========================

  /// 获取所有生词
  Future<List<VocabularyEntry>> getAllVocabulary() async {
    final db = await database;
    final maps = await db.query('vocabulary', orderBy: 'added_at DESC');
    return maps.map((map) => _vocabFromMap(map)).toList();
  }

  /// 添加生词
  Future<void> addVocabulary(VocabularyEntry entry) async {
    final db = await database;
    await db.insert('vocabulary', _vocabToMap(entry),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除生词
  Future<void> deleteVocabulary(String id) async {
    final db = await database;
    await db.delete('vocabulary', where: 'id = ?', whereArgs: [id]);
  }

  // ========================
  // Dictionary Cache
  // ========================

  /// 查询词典缓存
  Future<DictionaryCache?> getCachedDefinition(
      String word, String language) async {
    final db = await database;
    final maps = await db.query(
      'dictionary_cache',
      where: 'word = ? AND language = ?',
      whereArgs: [word, language],
    );
    if (maps.isEmpty) return null;
    return _dictCacheFromMap(maps.first);
  }

  /// 保存词典缓存
  Future<void> cacheDefinition(DictionaryCache cache) async {
    final db = await database;
    await db.insert('dictionary_cache', _dictCacheToMap(cache),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========================
  // Reading Time
  // ========================

  /// 确保 reading_time 表存在（自愈）
  Future<void> _ensureReadingTimeTable() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reading_time (
        book_id TEXT NOT NULL,
        date TEXT NOT NULL,
        seconds INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (book_id, date)
      )
    ''');
  }

  /// 增加阅读时长（秒），按日累计
  Future<void> addReadingTime(String bookId, int seconds) async {
    await _ensureReadingTimeTable();
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await db.execute('''
      INSERT INTO reading_time (book_id, date, seconds)
      VALUES (?, ?, ?)
      ON CONFLICT(book_id, date) DO UPDATE SET
        seconds = seconds + ?
    ''', [bookId, today, seconds, seconds]);
  }

  /// 获取今日阅读总时长（秒）
  Future<int> getTodayReadingSeconds() async {
    await _ensureReadingTimeTable();
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(seconds), 0) AS total
      FROM reading_time WHERE date = ?
    ''', [today]);
    return (result.first['total'] as num).toInt();
  }

  /// 获取某天阅读总时长（秒）
  Future<int> getReadingSecondsByDate(String date) async {
    await _ensureReadingTimeTable();
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(seconds), 0) AS total
      FROM reading_time WHERE date = ?
    ''', [date]);
    return (result.first['total'] as num).toInt();
  }

  /// 获取本周（周一到周日）每日阅读秒数
  Future<List<int>> getWeekReadingSeconds() async {
    await _ensureReadingTimeTable();
    final db = await database;
    final now = DateTime.now();
    // 计算本周一
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final dates = List.generate(7, (i) =>
      weekStart.add(Duration(days: i)).toIso8601String().substring(0, 10));

    final result = await db.rawQuery('''
      SELECT date, SUM(seconds) AS total
      FROM reading_time
      WHERE date >= ? AND date <= ?
      GROUP BY date
    ''', [dates.first, dates.last]);

    final map = <String, int>{};
    for (final row in result) {
      map[row['date'] as String] = (row['total'] as num).toInt();
    }
    return dates.map((d) => map[d] ?? 0).toList();
  }

  // ========================
  // Settings
  // ========================

  /// 获取设置值
  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  /// 设置值
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ========================
  // Notifications CRUD
  // ========================

  /// 插入通知
  Future<void> addNotification({
    required String type,
    required String title,
    required String body,
    String? bookId,
  }) async {
    final db = await database;
    await db.insert('notifications', {
      'type': type,
      'title': title,
      'body': body,
      'book_id': bookId,
      'read': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 获取未读通知数
  Future<int> getUnreadNotificationCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM notifications WHERE read = 0');
    return (result.first['c'] as int?) ?? 0;
  }

  /// 获取通知列表（最新在前）
  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    final db = await database;
    return db.query('notifications', orderBy: 'created_at DESC', limit: limit);
  }

  /// 标记为已读
  Future<void> markNotificationRead(int id) async {
    final db = await database;
    await db.update('notifications', {'read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// 标记所有为已读
  Future<void> markAllNotificationsRead() async {
    final db = await database;
    await db.update('notifications', {'read': 1}, where: 'read = 0');
  }

  // ========================
  // Mappers
  // ========================

  Map<String, dynamic> _bookToMap(Book book) {
    return {
      'id': book.id,
      'title': book.title,
      'author': book.author,
      'language': book.language,
      'cover': book.cover,
      'path': 'books/${book.id}',
      'added_at': book.addedAt?.millisecondsSinceEpoch ?? 0,
      'updated_at': book.updatedAt?.millisecondsSinceEpoch ?? 0,
      'last_read_at': book.lastReadAt?.millisecondsSinceEpoch,
    };
  }

  Book _bookFromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as String,
      title: map['title'] as String,
      author: map['author'] as String? ?? '',
      language: map['language'] as String? ?? 'en',
      cover: map['cover'] as String?,
      addedAt: map['added_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
      lastReadAt: map['last_read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_read_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> _progressToMap(ReadingProgress progress) {
    return {
      'book_id': progress.bookId,
      'chapter': progress.chapter,
      'paragraph': progress.paragraph,
      'sentence': progress.sentence,
      'char_offset': progress.charOffset,
      'percentage': progress.percentage,
      'updated_at': progress.updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    };
  }

  ReadingProgress _progressFromMap(Map<String, dynamic> map) {
    return ReadingProgress(
      bookId: map['book_id'] as String,
      chapter: map['chapter'] as int? ?? 0,
      paragraph: map['paragraph'] as int? ?? 0,
      sentence: map['sentence'] as int? ?? 0,
      charOffset: map['char_offset'] as int? ?? 0,
      percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> _vocabToMap(VocabularyEntry entry) {
    return {
      'id': entry.id,
      'word': entry.word,
      'translation': entry.translation,
      'definition': entry.definition,
      'example_sentence': entry.exampleSentence,
      'book_id': entry.bookId,
      'book_title': entry.bookTitle,
      'review_count': entry.reviewCount,
      'is_mastered': entry.isMastered ? 1 : 0,
      'added_at': entry.addedAt?.millisecondsSinceEpoch ?? 0,
      'last_reviewed_at': entry.lastReviewedAt?.millisecondsSinceEpoch,
    };
  }

  VocabularyEntry _vocabFromMap(Map<String, dynamic> map) {
    return VocabularyEntry(
      id: map['id'] as String,
      word: map['word'] as String,
      translation: map['translation'] as String?,
      definition: map['definition'] as String?,
      exampleSentence: map['example_sentence'] as String?,
      bookId: map['book_id'] as String?,
      bookTitle: map['book_title'] as String?,
      reviewCount: map['review_count'] as int? ?? 0,
      isMastered: (map['is_mastered'] as int?) == 1,
      addedAt: map['added_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int)
          : null,
      lastReviewedAt: map['last_reviewed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_reviewed_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> _dictCacheToMap(DictionaryCache cache) {
    return {
      'word': cache.word,
      'language': cache.language,
      'translation': cache.translation,
      'definition': cache.definition,
      'phonetic': cache.phonetic,
      'part_of_speech': cache.partOfSpeech,
      'cached_at': cache.cachedAt?.millisecondsSinceEpoch ?? 0,
    };
  }

  DictionaryCache _dictCacheFromMap(Map<String, dynamic> map) {
    return DictionaryCache(
      word: map['word'] as String,
      language: map['language'] as String,
      translation: map['translation'] as String?,
      definition: map['definition'] as String?,
      phonetic: map['phonetic'] as String?,
      partOfSpeech: map['part_of_speech'] as String?,
      cachedAt: map['cached_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['cached_at'] as int)
          : null,
    );
  }

  // ========================
  // Translation Status
  // ========================

  /// 保存翻译状态
  Future<void> saveTranslationStatus({
    required String bookId,
    required String bookTitle,
    required String language,
    required int sentenceCount,
    required String engineId,
    String status = 'completed',
  }) async {
    final db = await database;
    await db.insert(
      'translation_status',
      {
        'book_id': bookId,
        'book_title': bookTitle,
        'language': language,
        'sentence_count': sentenceCount,
        'engine_id': engineId,
        'status': status,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取所有翻译状态记录（按更新时间倒序）
  Future<List<Map<String, dynamic>>> getAllTranslationStatus() async {
    final db = await database;
    return db.query('translation_status', orderBy: 'updated_at DESC');
  }

  /// 获取指定书籍的翻译状态
  Future<List<Map<String, dynamic>>> getBookTranslationStatus(String bookId) async {
    final db = await database;
    return db.query(
      'translation_status',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'updated_at DESC',
    );
  }

  /// 删除指定书籍的所有翻译状态
  Future<void> deleteBookTranslationStatus(String bookId) async {
    final db = await database;
    await db.delete('translation_status', where: 'book_id = ?', whereArgs: [bookId]);
  }

  /// 删除指定书籍指定语言的翻译状态
  Future<void> deleteTranslationStatus(String bookId, String language) async {
    final db = await database;
    await db.delete(
      'translation_status',
      where: 'book_id = ? AND language = ?',
      whereArgs: [bookId, language],
    );
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}