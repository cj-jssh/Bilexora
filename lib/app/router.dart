import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'scaffold_with_nav_bar.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/book_source/book_source_screen.dart';
import '../features/vocabulary/vocabulary_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/library/translation_management_screen.dart';
import '../features/library/translation_detail_screen.dart';
import '../core/database/library_database.dart';

/// 检查是否首次启动
Future<bool> _isFirstLaunch() async {
  try {
    final db = LibraryDatabase();
    final value = await db.getSetting('first_launch_complete');
    return value != '1';
  } catch (_) {
    return true;
  }
}

/// 路由 Provider
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) async {
      // 只在首次加载时做一次引导页跳转
      if (state.matchedLocation == '/home') {
        final isFirst = await _isFirstLaunch();
        if (isFirst) return '/onboarding';
      }
      return null;
    },
    routes: [
      /// 首次引导页面
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      /// 底部 Tab 导航壳
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                name: 'library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/book-source',
                name: 'bookSource',
                builder: (context, state) => const BookSourceScreen(),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/reader/:bookId',
        name: 'reader',
        builder: (context, state) => ReaderScreen(
          bookId: state.pathParameters['bookId']!,
        ),
      ),
      GoRoute(
        path: '/vocabulary',
        name: 'vocabulary',
        builder: (context, state) => const VocabularyScreen(),
      ),
      GoRoute(
        path: '/translation-management',
        name: 'translationManagement',
        builder: (context, state) => const TranslationManagementScreen(),
      ),
      GoRoute(
        path: '/translation-detail/:bookId',
        name: 'translationDetail',
        builder: (context, state) => TranslationDetailScreen(
          bookId: state.pathParameters['bookId']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

/// 主题模式 Provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);