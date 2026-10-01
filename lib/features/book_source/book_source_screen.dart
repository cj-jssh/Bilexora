import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 书源搜索屏幕（占位）
class BookSourceScreen extends ConsumerWidget {
  const BookSourceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '书源管理',
            onPressed: () {
              // TODO: 书源管理
            },
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Book source search coming soon',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}