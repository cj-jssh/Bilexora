import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/dictionary_manager.dart';
import '../../core/state/dictionary_providers.dart';

/// 词典管理页面（与翻译引擎管理页面平行）
class DictionaryScreen extends ConsumerWidget {
  const DictionaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(dictSourcesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('词典管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '完成',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.menu_book, size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '长按拖拽排序，左滑删除，按排序优先返回结果',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          // 内置词典提示
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '内置词典（FreeDictionary API + ECDICT）始终可用，'
                    '添加外部词典后将优先查询外部词典。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: sources.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_book_outlined, size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text('暂无外部词典',
                            style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline)),
                        const SizedBox(height: 8),
                        Text('添加 SQLite 或 MDX 词典文件',
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.7))),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: sources.length,
                    onReorderItem: (oldIndex, newIndex) =>
                        ref
                            .read(dictSourcesProvider.notifier)
                            .reorder(oldIndex, newIndex),
                    proxyDecorator: (child, index, animation) =>
                        AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) => Material(
                            elevation: 4,
                            shadowColor: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                            child: child,
                          ),
                          child: child,
                        ),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      final notifier = ref.read(dictSourcesProvider.notifier);
                      return Dismissible(
                        key: ValueKey(source.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          final r = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('移除「${source.name}」？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('移除'),
                                ),
                              ],
                            ),
                          );
                          return r ?? false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.delete_outline,
                              color:
                                  Theme.of(context).colorScheme.onError),
                        ),
                        onDismissed: (_) => notifier.remove(source.id),
                        child: _DictCard(
                          source: source,
                          index: index,
                        ),
                      );
                    },
                  ),
          ),
          // 底部按钮
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加词典文件'),
                    onPressed: () =>
                        _addDictFile(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addDictFile(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'mdx'],
      );

      if (result.isEmpty) return;
      final filePath = result.first.path;
      if (filePath == null) return;

      // 检查是否已存在相同路径的词典
      final existing = ref.read(dictSourcesProvider);
      if (existing.any((s) => s.filePath == filePath)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('「${result.first.name}」已添加'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final ext = filePath.toLowerCase().split('.').last;
      final fileName = result.first.name;

      if (!context.mounted) return;

      if (ext == 'sqlite') {
        await _addSqliteDict(context, ref, filePath, fileName);
      } else if (ext == 'mdx') {
        await _addMdxDict(context, ref, filePath, fileName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('添加失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addSqliteDict(
      BuildContext context, WidgetRef ref, String filePath, String fileName) async {
    try {
      final source = await createSqliteDictSource(filePath);
      if (source == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无效的 SQLite 词典文件'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await ref.read(dictSourcesProvider.notifier).add(source);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加「${source.name}」(${source.entryCount} 词条)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('添加 SQLite 词典失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addMdxDict(
      BuildContext context, WidgetRef ref, String filePath, String fileName) async {
    final notifier = ref.read(dictSourcesProvider.notifier);
    // MDX 词典：支持占位，后续实现解析
    final source = DictSource(
      id: 'mdx_${DateTime.now().millisecondsSinceEpoch}',
      name: fileName.replaceAll(RegExp(r'\.mdx$'), ''),
      type: DictSourceType.mdx,
      filePath: filePath,
      language: 'en',
      description: 'MDX 词典（解析器待实现）',
      entryCount: 0,
    );
    await notifier.add(source);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 MDX 词典「${source.name}」（暂不支持查询，后续版本实现）'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

class _DictCard extends StatelessWidget {
  final DictSource source;
  final int index;

  const _DictCard({required this.source, required this.index});

  @override
  Widget build(BuildContext context) {
    final isSqlite = source.type == DictSourceType.sqlite;
    final isMdx = source.type == DictSourceType.mdx;
    final available = isSqlite; // MDX 暂不可用

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.drag_handle,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isMdx ? Icons.bookmark_border : Icons.menu_book,
                size: 22,
                color: available
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(source),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 状态指示
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: available ? Colors.green : Colors.orange.shade300,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  String _subtitle(DictSource source) {
    final parts = <String>[];
    switch (source.type) {
      case DictSourceType.sqlite:
        parts.add('SQLite');
        if (source.entryCount > 0) parts.add('${source.entryCount} 词条');
        parts.add('可用');
        break;
      case DictSourceType.mdx:
        parts.add('MDX');
        parts.add('待实现');
        break;
    }
    return parts.join(' · ');
  }
}