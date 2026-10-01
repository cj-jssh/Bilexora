<div align="center">
  <h1>📖 Bilexora</h1>
  <p><em>跨平台离线阅读与语言学习工具</em></p>
  <p>
    <img src="https://img.shields.io/badge/Flutter-3.47-blue?logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Dart-3.13-blue?logo=dart" alt="Dart">
    <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20Windows-lightgrey" alt="Platform">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  </p>
</div>

---

## 📑 目录

- [项目概述](#-项目概述)
- [快速开始](#-快速开始)
- [技术选型](#-技术选型)
- [数据架构](#-数据架构)
- [存储布局](#-存储布局)
- [核心模型](#-核心模型)
- [content.dat 二进制协议](#-contentdat-二进制协议)
- [翻译文件协议 content_langdat](#-翻译文件协议-content_langdat)
- [SQLite Library DB](#-sqlite-library-db)
- [翻译系统设计](#-翻译系统设计)
- [阅读器交互](#-阅读器交互)
- [项目结构](#-项目结构)
- [测试](#-测试)
- [构建部署](#-构建部署)
- [后续规划](#-后续规划)
- [许可证](#-许可证)

---

## 🎯 项目概述

**Bilexora** 是一个以**本地离线阅读**与**语言学习**为核心的多端阅读软件。它提供了从书籍导入、自定义排版、双语阅读到离线/AI 翻译的完整闭环体验。

### 主要能力

| 能力 | 状态 | 描述 |
|------|------|------|
| 📥 本地导入 | ✅ | 支持 EPUB / TXT 格式书籍导入 |
| 📐 标准化 | ✅ | 导入后统一序列化为内部 `content.dat` 二进制格式 |
| 🎨 自定义排版 | ✅ | 字号、行高、字间距、亮色 / 护眼 / 暗色主题 |
| 🌐 双语阅读 | ✅ | 交替 / 段落后 / 左右分栏三种布局，点击展示或立即展示 |
| 🔄 多翻译引擎 | ✅ | AI 引擎（OpenAI 兼容 API）与本地离线 Bergamot 引擎 |
| 💻 离线翻译 | ✅ | Bergamot (Mozilla NMT) 端侧 CPU 推理，无需联网 |
| ✍️ 点句翻译 | ✅ | 阅读时点击任意句子即用当前引擎翻译并持久化 |
| 📊 阅读统计 | ✅ | 阅读进度、今日时长、章节导航 |
| 🔔 通知中心 | ✅ | 翻译完成等事件通知 |
| 📚 生词本 | 🚧 | 数据层已就绪，交互完善中 |
| 🔍 书源搜索 | 🚧 | 界面占位，书源插件系统规划中 |
| 🔊 TTS / 校对 / 词典 | 📋 | 规划中 |

### 核心原则

> **书籍数据保存内容，Reader 负责排版，Sentence 是翻译的最小单位。**

1. **原始 EPUB / TXT 只用于导入**，阅读、翻译均基于标准化的 `content.dat`
2. **SQLite 负责书库索引和用户数据**，快速查询不扫描文件系统
3. **Book Package 自包含、可迁移**，单本书的数据（元数据 / 正文 / 译文 / 图片）独立成目录
4. **Chapter 是主要 I/O 单位**，通过章节索引一次 seek 随机访问，避免逐句读取
5. **Sentence（`charOffset` 全书句号）是翻译的关联主键**，原文与译文通过它对齐
6. **Reader 根据设备和用户设置自行排版**，内容和排版完全解耦
7. **正常阅读完全离线**，翻译仅在用户主动发起时使用本地引擎或访问 AI API
8. **翻译按语言分文件存储**，引擎与优先级元数据内嵌于每章数据块

---

## 🚀 快速开始

### 环境要求

| 工具 | 版本 |
|------|------|
| Flutter | >= 3.47.0 |
| Dart | >= 3.13.0 |
| Android Studio / Xcode / Visual Studio | 视目标平台需要 |

> 离线翻译依赖 `plugins/bergamot_translator` 原生插件，首次构建会编译 C++ 代码，Android 需 NDK，Windows 需 C++ 桌面开发工作负载。

### 克隆与运行

```bash
git clone https://github.com/your-username/bilexora.git
cd bilexora
flutter pub get
flutter run
```

指定平台：

```bash
flutter run -d windows   # Windows
flutter run -d android   # Android
flutter run -d ios       # iOS（需 macOS）
```

### 代码检查与测试

```bash
flutter analyze
flutter test
```

---

## 🛠 技术选型

| 层次 | 技术 | 选型理由 |
|------|------|----------|
| **跨平台框架** | Flutter 3.47 | 一套代码覆盖 iOS / Android / Windows |
| **语言** | Dart 3.13 | 空安全、模式匹配、Records，性能优秀 |
| **状态管理** | Riverpod | 编译安全、依赖注入友好 |
| **路由** | go_router | 声明式路由、路径参数、嵌套路由 |
| **本地存储** | SQLite (sqflite) | 零依赖嵌入式数据库 |
| **书籍数据** | 自定义二进制 `content.dat` | 单文件自包含，Varint 压缩，按章随机访问 |
| **翻译数据** | 自定义二进制 `content_{lang}.dat` | 按语言分文件，章节对齐，全量重写自压缩 |
| **网络请求** | http | AI 翻译 API 调用 |
| **文件解析** | xml + archive | 纯 Dart 解析 EPUB（ZIP + XHTML），跨平台一致 |
| **离线翻译** | Bergamot (Mozilla NMT) | 端侧 CPU 推理，隐私友好，模型按语言对下载 |

---

## 🗄 数据架构

### 数据职责矩阵

| 数据 | 存储位置 | 作用 |
|------|----------|------|
| 书库列表 | SQLite `books` | 快速展示、搜索、排序 |
| 阅读进度 | SQLite `reading_progress` | 恢复阅读位置 |
| 生词本 | SQLite `vocabulary` | 用户学习数据 |
| 词典缓存 | SQLite `dictionary_cache` | 查询缓存 |
| 应用设置 | SQLite `settings` | 用户偏好、翻译引擎配置 |
| 阅读时长 | SQLite `reading_time` | 按日累计统计 |
| 通知 | SQLite `notifications` | 事件通知 |
| 翻译状态 | SQLite `translation_status` | 翻译任务记录 |
| Book 元数据 | `book.json` | 单书自描述 |
| 正文+结构 | `content.dat` | Chapter / Paragraph / Sentence 数据 |
| 翻译结果 | `content_{lang}.dat` | 按语言独立存储的译文 |
| 图片资源 | `images/` | 书籍内嵌图片 |

---

## 🗂 存储布局

```
library/
├── library.db                      # SQLite 书库索引 + 用户数据
│
└── books/                          # Book Package 目录
    ├── book_001/
    │   ├── book.json               # 元数据（Book.toJson 序列化）
    │   ├── content.dat             # 正文二进制数据
    │   ├── content_zh.dat          # 中文译文（可选，按语言独立）
    │   ├── content_fr.dat          # 法文译文（可选）
    │   └── images/
    │       └── chapter1.png
    │
    └── book_002/
        └── ...
```

---

## 🧩 核心模型

```
Book
 └── Chapter（I/O 单位）
      └── ContentBlock
           ├── Paragraph（结构单位）
           │    ├── Sentence（核心最小单位）
           │    ├── Sentence
           │    └── Sentence
           └── Image（图片资源）

Sentence {
    int index,         // 句内序号
    String text,       // 原文
    int charOffset,    // 全书统一句号（globalIndex）
}

ContentBlock {
    String blockType,         // "paragraph" | "image"
    Paragraph? paragraph,     // paragraph 类型时
    String? imagePath,        // image 类型时
    String? altText,          // image 类型时
}
```

### 关键约束

- **`charOffset` 是全书统一的句子编号**，导入时按段落顺序分配，翻译与展示都通过它关联
- Chapter 是**随机访问单位**：通过 `content.dat` 的 Chapter Index 可直接 seek 到指定章节
- 阅读器加载章节时**预读后续 2 章**，翻页无感知

---

## 📄 content.dat 二进制协议

**协议定义**: `lib/core/models/content_dat_constants.dart`
**读取器**: `lib/core/storage/content_dat_reader.dart` · **写入器**: `lib/core/storage/content_dat_writer.dart`

Magic: `"BILXDATA"`（8 字节）。单文件自包含，支持按章节随机访问。

### 文件整体布局

```
┌──────────────────────────────────────────────────────┐
│  Header（24 字节，定长）                              │
├──────────────────────────────────────────────────────┤
│  Content Data（变长）                                 │
│    Chapter 0: 段落/图片/句子数据                      │
│    Chapter 1: ...                                    │
├──────────────────────────────────────────────────────┤
│  Chapter Index（变长，写于 Content Data 之后）        │
│    Chapter 0: ID | Title | SentenceCount | Offset ... │
│    Chapter 1: ...                                    │
└──────────────────────────────────────────────────────┘
```

### Header 结构（24 字节）

| 偏移 | 大小 | 字段 | 编码 | 说明 |
|------|------|------|------|------|
| 0 | 8 | Magic | UTF-8 | `"BILXDATA"` |
| 8 | 4 | Version | uint32 LE | 当前为 `1` |
| 12 | 3 | Chapter Count | Varint（槽位） | 章节数 |
| 15 | 5 | Chapter Index Offset | Varint（槽位） | Index 起始偏移 |
| 20 | 3 | Chapter Index Length | Varint（槽位） | Index 字节长度 |
| 23 | 1 | Reserved | `0x00` | 预留 |

> **Varint 槽位**：Header 中的 Varint 字段分配了固定大小的字节槽。读取时从槽位起始处按 Varint 规则解析；写入时不足槽位高位补 0。

### Chapter Index — 变长

每个章节一条记录，所有字段均用 Varint 编码：

| 字段 | 编码 | 说明 |
|------|------|------|
| Chapter ID | Varint | 章节编号（从 0 开始） |
| Title | Varint(len) + UTF-8 | 章节标题 |
| Sentence Count | Varint | 该章节总句子数 |
| Content Offset | Varint | 该章节内容在文件中的字节偏移 |
| Content Length | Varint | 该章节内容的字节长度 |

### Content Data — 变长结构

```
Block Type (1 byte)
  ├── 0 = Paragraph
  │     └── Sentence Count (Varint)
  │           ├── Sentence 0:
  │           │     ├── Global Index (Varint)   ← 即 sentence.charOffset
  │           │     └── Text: Varint(len) + UTF-8
  │           └── ...
  └── 1 = Image
        ├── Sentence Count = 0 (Varint)
        ├── Image Path: Varint(len) + UTF-8
        └── Alt Text: Varint(len) + UTF-8
```

### 设计关键

1. **Chapter Index 在 Content Data 之后**：先写正文得到实际 offset/length，再写 Index，最后回填 Header
2. **`sentence.charOffset` 即为 Global Index**：写入时直接取值而非写时计数，确保与导入时分配的句号一一对应
3. **一次 seek 随机访问**：读任意章节 = 读 Header → seek 到 Index → seek 到章节数据
4. **翻译数据外置**：不内嵌于 `content.dat`，独立为 `content_{lang}.dat`

### 读写示例

```dart
// 写入
final bytes = ContentDatWriter(10 * 1024 * 1024).write(book);
await File('content.dat').writeAsBytes(bytes);

// 读取：Header + 按章节随机访问
final reader = ContentDatReader(await File('content.dat').readAsBytes());
print('章节数: ${reader.chapterCount}');

final chapter = reader.readChapter(3); // 1 次 seek + 顺序读
for (final block in chapter!.blocks) {
  block.when(
    paragraph: (p) {
      for (final s in p.sentences) {
        print('${s.charOffset}: ${s.text}');
      }
    },
    image: (path, alt) => print('图片: $path'),
  );
}
```

---

## 📄 翻译文件协议 content_langdat

**代码**: `lib/core/storage/translation_file.dart`

翻译数据按语言独立存储为 `content_{lang}.dat`，与 `content.dat` 章节对齐。Magic: `"TRLX"`（4 字节）。

### 文件整体布局

```
┌────────────────────────────────────────────────────┐
│ Header（16 字节，定长）                            │
│   Magic (4B): "TRLX"                             │
│   Version (2B, uint16)                           │
│   Chapter Count (2B, uint16)                     │
│   Chapter Index Offset (4B, uint32)              │
│   Chapter Index Length (4B, uint32)              │
├────────────────────────────────────────────────────┤
│ Translation Data（变长，按章节）                   │
│   Chapter 0:                                      │
│     engineId(V) | priority(V) |                   │
│     sentenceCount(V) | text0(V) | text1(V) | ...  │
│   Chapter 1: ...                                  │
├────────────────────────────────────────────────────┤
│ Chapter Index（变长）                              │
│   Entry 0: contentOffset(V) | contentLength(V)    │
│   Entry 1: ...                                    │
└────────────────────────────────────────────────────┘
```

> (V) = Varint 编码

### 章节翻译数据块

```
engineId:      Varint(len) + UTF-8   ← 产生该章译文的引擎 ID
priority:      Varint                ← 引擎优先级
sentenceCount: Varint                ← 本章句子数
text 0..n:     Varint(len) + UTF-8   ← 按章内句序排列的译文
```

**不存储 globalIndex**——第 2 章第 0 句的 globalIndex = 前两章句数之和，由 content.dat 的每章句数推算。

### 写入模型：全量重写、同章合并

每次 `append*` 写入的流程：

1. 读旧文件的 Header + Chapter Index
2. **同章合并**：保留该章已有译文，新译文按句位覆盖（逐句追加互不丢句）
3. 重写整个文件：Header + 旧数据区 + 新章块 + 新 Index + 回填 Header

文件每次落盘都是紧凑完整的，**无碎片、无垃圾空间、无需压缩（GC）**。所有写入方（单句点击、整章翻译、全书批量）共用同一入口。

### 损坏防护

读取器对任何脏数据（垃圾索引条目、越界、非法 UTF-8）都**降级为"该章无翻译"返回 null**，绝不抛异常中断阅读；被污染的章节重新翻译一次即可自愈。

### 读写示例

```dart
final fm = TranslationFileManager(
  p.join(libraryPath, 'books', bookId),
  bookId: bookId,
);

// ── 读取全部翻译为 {globalIndex → text} ──
final map = await fm.loadTranslation('zh',
    perChapterSentenceCounts: [100, 85, 92]);

// ── 批量追加（自动按章节分组，与已有译文合并）──
await fm.appendTranslation(
  lang: 'zh', engineId: 'deepseek', priority: 5,
  results: [(globalIndex: 42, text: '你好'), (globalIndex: 43, text: '世界')],
);

// ── 直接追加一整章 ──
await fm.appendChapterTranslation(
  lang: 'zh', engineId: 'deepseek', priority: 5,
  chapterIndex: 9, texts: ['你好', '世界'], totalChapterCount: 20,
);

// ── 按引擎删除翻译 ──
await fm.deleteEngineFromLanguage('zh', 'deepseek');

// ── 统计 / 元信息 ──
await fm.translationSentenceCount('zh');        // 已翻译句数
await fm.listEnginesForLanguage('zh');          // [(engineId: 'deepseek', count: 85)]
await fm.listAvailableLanguages();              // ['zh', 'fr']
```

---

## 🗄 SQLite Library DB

**代码**: `lib/core/database/library_database.dart`

| 表 | 用途 | 关键字段 |
|----|------|----------|
| `books` | 书库索引 | id, title, author, language, cover, path, added_at, last_read_at |
| `reading_progress` | 阅读进度 | book_id, chapter, paragraph, percentage, updated_at |
| `vocabulary` | 生词本 | word, translation, book_id, review_count, is_mastered |
| `dictionary_cache` | 词典缓存 | word, language, translation, phonetic |
| `settings` | KV 存储 | key, value |
| `reading_time` | 阅读时长 | book_id, date, seconds |
| `notifications` | 通知 | type, title, body, book_id, read |
| `translation_status` | 翻译任务 | book_id, language, sentence_count, engine_id |

### 阅读进度写入策略

```
用户滚动 → 内存更新 → 停止操作 ~1500ms（防抖）→ 写入 SQLite
```

---

## 🌐 翻译系统设计

### 引擎架构

引擎通过 `TranslationEngine` 模型统一管理，配置持久化于 `settings` 表，支持排序，**排序第一的为默认引擎**：

```dart
class TranslationEngine {
  final String id;       // "local_bergamot" 或自定义 AI 引擎 id
  final String name;
  final TranslationEngineType type;  // local | online
  final String? apiKey;  // AI 引擎
  final String? apiUrl;  // OpenAI 兼容 base URL
  final String? modelName;
}
```

| 引擎类型 | 实现 | 特点 |
|----------|------|------|
| 本地（Bergamot） | `LocalTranslationService` | 端侧推理、完全离线、仅支持 EN ↔ X |
| AI（OpenAI 兼容） | `translateWithAI()` | 任意语言对、按 token 分批、3 次指数退避重试 |

### 统一的翻译入口

所有触发场景（点句 / 整章 / 全书批量）共用同一套流程组件：

```
resolveLocalDirection()   ← 方向解析：书语==母语 ? 翻向学习语 : 翻向母语
ensureBergamotModel()     ← 模型保障：检查 → 确认下载 → 模态进度 → 安装标记
BatchFileWriter           ← 落盘：缓冲达阈值（1% 句数或 64KB）后台写盘，链式串行
```

### 单句点击翻译流程

```
读者点击「暂无对应译文」
    ↓
_translateSingleSentence(globalIndex)   ← 用当前默认引擎
    ↓
从已加载块中找到原文 → AI: translateWithAI() / 本地: Bergamot
    ↓
fm.appendTranslation() 持久化（同章合并，不丢已有译文）
    ↓
更新内存 _translationMap，按展示模式显示译文
```

### 离线翻译引擎 — Bergamot

**代码**: `lib/features/translation/local_translation_service.dart`

| 特性 | 说明 |
|------|------|
| **翻译方式** | 直接 A→B；非英语对（如 zh→fr）自动经英语中转 A→en→B |
| **模型匹配** | 严格按方向前缀匹配 `model.{from}{to}.bin`，避免误用反向模型产生乱码 |
| **重复句去重** | 同文本只送引擎一次，结果回填所有重复句 |
| **批量推理** | 每 16 句一批调用原生引擎 |
| **取消机制** | 全局取消标记，取消时已完成的译文仍然落盘 |
| **进度上报** | `ValueNotifier<double>`，UI 节流监听 |

### 模型下载

语言模型（约 30MB/语言）按需从镜像源下载，经 `ensureBergamotModel()` 引导：确认对话框 → 模态下载进度 → 以下载结果核实安装状态 → 更新全局已安装语言表。应用启动时也会静默预载母语/学习语言的双向模型。

---

## 📖 阅读器交互

### 双语布局

| 模式 | 布局 |
|------|------|
| `alternating` | 交替显示：原文一行，译文一行 |
| `paragraph` | 段落后显示：全段原文后紧跟全段译文 |
| `side_by_side` | 左右分栏：原文在左，译文在右 |

### 译文展示模式

| 模式 | 行为 |
|------|------|
| `immediate` | 有译文直接跟随原文显示 |
| `on_tap` | 点击译文区域后才显示，再次点击隐藏 |

### 译文三态交互

```dart
// _revealedSentences 的语义随展示模式切换：
//   on_tap:    集合包含 → 可见
//   immediate: 集合不包含 → 可见
final showNow = hasT && (showMode == 'on_tap' ? isRev : !isRev);

// ① 无译文 → 点击 → 显示「暂无对应译文」占位
// ② 点击占位 → 用默认引擎翻译 → 展示
// ③ 有译文 → 点击 → 切换显示/隐藏
```

### 排版设置

字号、行高、字间距独立可调；亮色 / 护眼（暖色）/ 暗色三种主题；设置持久化于 SQLite，与书籍内容完全解耦。

---

## 📂 项目结构

```text
lib/
├── main.dart                          # 应用入口（覆盖 libraryPathProvider、启动预载模型）
│
├── app/                               # 应用层
│   ├── app.dart                       # MaterialApp.router 配置
│   ├── router.dart                    # go_router 路由表
│   ├── scaffold_with_nav_bar.dart     # 底部导航栏
│   └── theme.dart                     # Material 3 亮/暗主题
│
├── core/                              # 核心基础设施
│   ├── constants/
│   │   └── constants.dart             # 全局常量
│   ├── database/
│   │   └── library_database.dart      # SQLite 书库
│   ├── models/                        # 领域模型
│   │   ├── book.dart                  # Book（+ translations 元数据）
│   │   ├── chapter.dart               # Chapter
│   │   ├── content_block.dart         # ContentBlock
│   │   ├── content_dat_constants.dart # content.dat 协议常量
│   │   ├── paragraph.dart / sentence.dart
│   │   ├── reading_progress.dart / vocabulary.dart / dictionary_cache.dart
│   │   └── models.dart                # barrel 导出
│   ├── storage/                       # 文件存储
│   │   ├── book_importer.dart         # EPUB / TXT → Book 模型（含分句、句号分配）
│   │   ├── book_package_manager.dart  # Book Package 目录管理
│   │   ├── content_dat_reader.dart    # content.dat 读取器
│   │   ├── content_dat_writer.dart    # content.dat 写入器
│   │   └── translation_file.dart      # content_{lang}.dat 读写（含 Varint 编解码）
│   ├── utils/
│   │   ├── text_utils.dart            # 分句等文本处理
│   │   ├── translation_utils.dart     # AI 翻译调用 + 错误消息转译
│   │   └── utils.dart                 # barrel 导出
│   └── state/
│       └── app_state.dart             # 全局 Riverpod 状态
│
├── features/                          # 功能模块
│   ├── book_source/book_source_screen.dart        # 书源（占位）
│   ├── home/home_screen.dart                      # 首页：继续阅读 / 今日时长 / 通知
│   ├── library/
│   │   ├── library_screen.dart                    # 书库 + 全书批量翻译
│   │   ├── translation_management_screen.dart     # 翻译任务管理（进度/取消）
│   │   └── translation_detail_screen.dart         # 单书译文详情（引擎分布/删除）
│   ├── reader/reader_screen.dart                  # 阅读器（核心 UI：排版/双语/点句翻译）
│   ├── settings/
│   │   ├── settings_screen.dart                   # 语言/排版/展示设置
│   │   └── translation_engine_screen.dart         # 翻译引擎配置 + 语言包下载
│   ├── translation/
│   │   ├── bergamot_flow.dart                     # 共享：方向解析 + 模型下载保障
│   │   ├── local_translation_service.dart         # Bergamot 离线翻译 + BatchFileWriter
│   │   └── translation_task_manager.dart          # 批量翻译任务状态
│   └── vocabulary/vocabulary_screen.dart          # 生词本
│
test/
├── content_dat_roundtrip_test.dart    # content.dat 字节级往返完整性
└── translation_file_test.dart         # content_{lang}.dat 读写/合并/损坏防护

plugins/
└── bergamot_translator/               # Bergamot (Mozilla NMT) Flutter 绑定（FFI）
```

### 架构分层

```text
UI（Widgets）
    ↓
Feature（Riverpod Providers / StateNotifier）
    ↓
Service（LocalTranslationService, TranslationFileManager ...）
    ↓
Repository（LibraryDatabase, BookPackageManager, BookImporter）
    ↓
Data（SQLite / 二进制文件 / HTTP API / 原生 FFI）
```

---

## 🧪 测试

```bash
flutter test
```

| 测试文件 | 覆盖内容 |
|----------|----------|
| `content_dat_roundtrip_test.dart` | 多章节写入→读取后 globalIndex 连续且与文本一一对应；Varint 大数值边界（>2²¹）；含图片块时句子不串位 |
| `translation_file_test.dart` | 单章读写往返；跨章分组与空位占位；**连续逐句追加互不覆盖**；**同章二次追加合并**；引擎隔离删除；坏 magic/截断/垃圾字节不抛异常 |

---

## 📦 构建部署

### Windows

```bash
flutter build windows --release
# 输出: build/windows/x64/runner/Release/
```

### Android

```bash
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk

flutter build appbundle --release   # Google Play
# 输出: build/app/outputs/bundle/release/app-release.aab
```

### iOS（需 macOS + Xcode）

```bash
flutter build ios --release
# 然后通过 Xcode 归档导出 IPA
```

---

## 🧭 后续规划

- [ ] 书源插件系统（网络搜书 / 下载）
- [ ] 人工逐句校对与多版本管理
- [ ] 词典查询 UI（点词查询 + 词典缓存）
- [ ] 生词本交互完善与复习
- [ ] TTS 朗读
- [ ] Anki 导出
- [ ] PDF 导入
- [ ] 阅读统计图表
- [ ] 多设备同步（WebDAV / iCloud）
- [ ] 自定义字体导入

---

## 📄 许可证

MIT License © 2024-2026 Bilexora

---

<div align="center">
  <sub>Built with ❤️ using Flutter</sub>
</div>
