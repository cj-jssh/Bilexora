import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/library_database.dart';
import '../../core/models/models.dart';

/// 生词本屏幕
class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  List<VocabularyEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  Future<void> _loadVocabulary() async {
    try {
      final db = LibraryDatabase();
      final entries = await db.getAllVocabulary();
      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生词本'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空所有生词',
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border, size: 72, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '生词本还是空的',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            '在双语阅读中点击单词，即可加入生词本',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadVocabulary,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _entries.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 72, endIndent: 16),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _VocabTile(
            entry: entry,
            onDelete: () => _deleteEntry(entry.id),
            onTap: () => _showEntryDetail(entry),
          );
        },
      ),
    );
  }

  Future<void> _deleteEntry(String id) async {
    await LibraryDatabase().deleteVocabulary(id);
    _loadVocabulary();
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空生词本'),
        content: Text('确定要删除全部 ${_entries.length} 个生词吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除全部', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final e in _entries) {
        await LibraryDatabase().deleteVocabulary(e.id);
      }
      _loadVocabulary();
    }
  }

  void _showEntryDetail(VocabularyEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(entry.word, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
            if (entry.translation != null && entry.translation!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(entry.translation!, style: TextStyle(fontSize: 16, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
            if (entry.definition != null && entry.definition!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(entry.definition!, style: const TextStyle(fontSize: 14, height: 1.5)),
              ),
            ],
            if (entry.exampleSentence != null) ...[
              const SizedBox(height: 12),
              Text('例句', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(ctx).colorScheme.primary)),
              const SizedBox(height: 4),
              Text(entry.exampleSentence!, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.4)),
            ],
            if (entry.bookTitle != null) ...[
              const SizedBox(height: 12),
              Text('来自: ${entry.bookTitle}', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Text('复习次数: ${entry.reviewCount}', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (entry.isMastered)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green),
                    SizedBox(width: 4),
                    Text('已掌握', style: TextStyle(fontSize: 12, color: Colors.green)),
                  ]),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _VocabTile extends StatelessWidget {
  final VocabularyEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _VocabTile({
    required this.entry,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          entry.word.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(entry.word, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: entry.translation != null && entry.translation!.isNotEmpty
          ? Text(entry.translation!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.isMastered)
            Icon(Icons.check_circle, size: 20, color: Colors.green[400]),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error.withValues(alpha: 0.7)),
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}