import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/database/library_database.dart';
import '../../core/models/models.dart';
import '../library/library_screen.dart';

final dailyReadingGoalProvider = StateProvider<int>((ref) => 30);

final todayReadingSecondsProvider = FutureProvider<int>((ref) async {
  final db = LibraryDatabase();
  return db.getTodayReadingSeconds();
});

final readingWordCountProvider = StateProvider<int>((ref) => 0);
final lookupWordCountProvider = StateProvider<int>((ref) => 0);

final weeklySecondsProvider = FutureProvider<List<int>>((ref) async {
  final db = LibraryDatabase();
  return db.getWeekReadingSeconds();
});

final unreadNotificationCountProvider = FutureProvider<int>((ref) async {
  final db = LibraryDatabase();
  return db.getUnreadNotificationCount();
});

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = LibraryDatabase();
  return db.getNotifications();
});

int _todayWeekdayIndex() => DateTime.now().weekday - 1;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentBooksProvider);
    final unreadAsync = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('主页'),
        actions: [
          _NotificationButton(unreadCountAsync: unreadAsync),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: recentAsync.when(
        data: (recent) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _SectionTitle(context, '继续阅读'),
                  const SizedBox(height: 12),
                  _ContinueReadingCards(recent: recent),
                ] else ...[
                  const SizedBox(height: 80),
                  _buildEmptyHint(context),
                ],
                const SizedBox(height: 28),
                _SectionTitle(context, '概览'),
                const SizedBox(height: 12),
                _buildOverview(context, ref),
                const SizedBox(height: 20),
                _buildWeekRings(context, ref),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 80),
              _buildEmptyHint(context),
              const SizedBox(height: 28),
              _SectionTitle(context, '概览'),
              const SizedBox(height: 12),
              _buildOverview(context, ref),
              const SizedBox(height: 20),
              _buildWeekRings(context, ref),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHint(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.menu_book_rounded, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('还没有正在阅读的书籍', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('从书库中选择一本书开始阅读', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }

  Widget _buildOverview(BuildContext context, WidgetRef ref) {
    final todaySecondsAsync = ref.watch(todayReadingSecondsProvider);
    final dailyGoal = ref.watch(dailyReadingGoalProvider);
    final wordCount = ref.watch(readingWordCountProvider);
    final lookupCount = ref.watch(lookupWordCountProvider);
    final todayMinutes = todaySecondsAsync.when(data: (s) => (s / 60).round(), loading: () => 0, error: (_, _) => 0);
    final progress = dailyGoal > 0 ? (todayMinutes / dailyGoal).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(flex: 5, child: SizedBox(
            height: 130,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SemiCirclePainter(
                    progress: progress,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    progressColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('今日阅读', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('$todayMinutes / $dailyGoal 分钟', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
              ])),
            ]),
          )),
          const SizedBox(width: 24),
          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _StatTile(icon: Icons.auto_stories_outlined, label: '阅读词汇量', value: '$wordCount', unit: '词'),
            const SizedBox(height: 16),
            _StatTile(icon: Icons.search_outlined, label: '查询单词', value: '$lookupCount', unit: '次'),
          ])),
        ],
      ),
    );
  }

  Widget _buildWeekRings(BuildContext context, WidgetRef ref) {
    final weekSecondsAsync = ref.watch(weeklySecondsProvider);
    final dailyGoal = ref.watch(dailyReadingGoalProvider);
    final todayIdx = _todayWeekdayIndex();
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final weekMinutes = weekSecondsAsync.when(data: (list) => list.map((s) => (s / 60).round()).toList(), loading: () => List.filled(7, 0), error: (_, _) => List.filled(7, 0));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final minutes = i < weekMinutes.length ? weekMinutes[i] : 0;
          final pct = dailyGoal > 0 ? (minutes / dailyGoal).clamp(0.0, 1.0) : 0.0;
          return _WeekRing(label: labels[i], progress: pct, isToday: i == todayIdx, completed: minutes >= dailyGoal);
        }),
      ),
    );
  }
}

// ── 通知按钮（带红点） ──

class _NotificationButton extends ConsumerWidget {
  final AsyncValue<int> unreadCountAsync;
  const _NotificationButton({required this.unreadCountAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = unreadCountAsync.when(data: (c) => c, loading: () => 0, error: (_, _) => 0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: '通知',
          onPressed: () => _showNotifications(context, ref),
        ),
        if (unread > 0)
          Positioned(
            right: 6, top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}

void _showNotifications(BuildContext context, WidgetRef ref) {
  final db = LibraryDatabase();
  db.markAllNotificationsRead();
  ref.invalidate(unreadNotificationCountProvider);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('通知', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          const Divider(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: db.getNotifications(),
              builder: (ctx, snap) {
                if (!snap.hasData || snap.data!.isEmpty) {
                  return const Center(child: Text('暂无通知', style: TextStyle(color: Colors.grey)));
                }
                return ListView.separated(
                  controller: scrollController,
                  itemCount: snap.data!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final n = snap.data![i];
                    final title = n['title'] as String? ?? '';
                    final body = n['body'] as String? ?? '';
                    final createdAt = DateTime.fromMillisecondsSinceEpoch(n['created_at'] as int);
                    return ListTile(
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(body, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
}

// ── 子组件 ──

class _SectionTitle extends StatelessWidget {
  final BuildContext context;
  final String title;
  const _SectionTitle(this.context, this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
    );
  }
}

class _ContinueReadingCards extends ConsumerWidget {
  final List<({Book book, ReadingProgress? progress})> recent;
  const _ContinueReadingCards({required this.recent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryPath = ref.watch(libraryPathProvider);
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: recent.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = recent[index];
          return _ContinueCard(book: item.book, progress: item.progress, libraryPath: libraryPath);
        },
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Book book;
  final ReadingProgress? progress;
  final String libraryPath;
  const _ContinueCard({required this.book, required this.progress, required this.libraryPath});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.cover != null ? p.join(libraryPath, 'books', book.id, 'images', book.cover!) : null;
    final pct = (progress?.percentage ?? 0.0).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () => context.push('/reader/${book.id}'),
      child: Container(
        width: 260,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(width: 52, height: 72, color: Theme.of(context).colorScheme.primaryContainer,
              child: _coverWidget(coverPath, 52, 72)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text(book.author.isNotEmpty ? book.author : '未知作者', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow))),
              const SizedBox(width: 6),
              Text('${(pct * 100).round()}%', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ])),
        ]),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  const _StatTile({required this.icon, required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(unit, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ]),
        ]),
      ]),
    );
  }
}

class _WeekRing extends StatelessWidget {
  final String label;
  final double progress;
  final bool isToday;
  final bool completed;
  const _WeekRing({required this.label, required this.progress, required this.isToday, required this.completed});

  @override
  Widget build(BuildContext context) {
    final textColor = isToday ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(width: 38, child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 34, height: 34,
        child: CustomPaint(
          size: const Size(34, 34),
          painter: _RingPainter(progress: progress, backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, progressColor: Theme.of(context).colorScheme.primary),
          child: Center(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: isToday ? FontWeight.w600 : FontWeight.w400, color: textColor))),
        ),
      ),
    ]));
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  _RingPainter({required this.progress, required this.backgroundColor, required this.progressColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    const sw = 4.0;
    final bg = Paint()..color = backgroundColor..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);
    if (progress > 0) {
      final fg = Paint()..color = progress >= 1.0 ? progressColor : progressColor..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, math.pi * 2 * progress.clamp(0.0, 1.0), false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

class _SemiCirclePainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  _SemiCirclePainter({required this.progress, required this.backgroundColor, required this.progressColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width * 0.38;
    const sw = 10.0;
    final bg = Paint()..color = backgroundColor..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi, math.pi, false, bg);
    if (progress > 0) {
      final fg = Paint()..color = progressColor..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), math.pi, math.pi * progress.clamp(0.0, 1.0), false, fg);
    }
    if (progress > 0.005 && progress < 0.995) {
      final endAngle = math.pi + math.pi * progress;
      final dot = Paint()..color = progressColor..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(center.dx + radius * math.cos(endAngle), center.dy + radius * math.sin(endAngle)), sw / 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SemiCirclePainter old) => old.progress != progress;
}

Widget _coverWidget(String? coverPath, double w, double h) {
  if (coverPath != null) {
    final file = File(coverPath);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover, width: w, height: h, errorBuilder: (_, _, _) => const Icon(Icons.book, size: 24));
    }
  }
  return const Icon(Icons.book, size: 24);
}