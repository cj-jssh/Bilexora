import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 底部导航栏标签定义
enum AppTab {
  home(label: '主页'),
  library(label: '书库'),
  bookSource(label: '书源');

  final String label;

  const AppTab({required this.label});

  /// 构建图标
  Widget buildIcon({required bool isSelected, required ColorScheme colorScheme}) {
    final color = isSelected
        ? (colorScheme.brightness == Brightness.dark ? Colors.white : Colors.black)
        : (colorScheme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.4));

    switch (this) {
      case AppTab.home:
        return Icon(Icons.home_rounded, size: 22, color: color);
      case AppTab.library:
        return _LibraryIcon(color: color);
      case AppTab.bookSource:
        return _BookStackIcon(color: color);
    }
  }
}

/// 书库图标：左侧竖着一本书 + 右侧打开的书
class _LibraryIcon extends StatelessWidget {
  final Color color;
  const _LibraryIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24, height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -2, bottom: 0,
            child: Icon(Icons.menu_book_rounded, size: 20, color: color),
          ),
          Positioned(
            left: -1, bottom: 0,
            child: Transform.rotate(
              angle: -0.15,
              child: Icon(Icons.book_rounded, size: 20, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 书源图标：四本高低不同的书（CustomPainter）
class _BookStackIcon extends StatelessWidget {
  final Color color;
  const _BookStackIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24, height: 22,
      child: CustomPaint(
        size: const Size(24, 22),
        painter: _BookStackPainter(color: color),
      ),
    );
  }
}

class _BookStackPainter extends CustomPainter {
  final Color color;
  _BookStackPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    const bw = 4.0, gap = 2.0;
    final maxH = size.height;
    final heights = [maxH * 0.55, maxH * 0.85, maxH, maxH * 0.7];
    final totalW = bw * 4 + gap * 3;
    final startX = (size.width - totalW) / 2;
    for (int i = 0; i < 4; i++) {
      final x = startX + i * (bw + gap);
      final h = heights[i];
      final y = maxH - h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, h), const Radius.circular(0.8)),
        paint,
      );
      final spine = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x + 0.5, y + 1, 1.0, h - 2), const Radius.circular(0.3)),
        spine,
      );
    }
  }

  @override
  bool shouldRepaint(_BookStackPainter old) => old.color != color;
}

// ── 毛玻璃容器 Widget ─────────────────────────────

/// 一个带毛玻璃效果的圆角容器
class _GlassBox extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _GlassBox({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: isDark ? _darkBlur : _lightBlur,
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── 主导航栏 ─────────────────────────────────────

class ScaffoldWithNavBar extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _searchProgress;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _searchProgress = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    if (_animCtrl.isAnimating) return;
    if (_isSearchOpen) {
      _searchFocus.unfocus();
      _searchCtrl.clear();
      _animCtrl.reverse();
      setState(() => _isSearchOpen = false);
    } else {
      setState(() => _isSearchOpen = true);
      _animCtrl.forward().then((_) => _searchFocus.requestFocus());
    }
  }

  void _onTab(int i) {
    if (_isSearchOpen) _toggleSearch();
    widget.navigationShell.goBranch(i,
        initialLocation: i == widget.navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(children: [
        widget.navigationShell,
        Positioned(left: 0, right: 0, bottom: 0, child: _navBar(cs)),
      ]),
    );
  }

  Widget _navBar(ColorScheme cs) {
    final tabs = AppTab.values;
    final cur = widget.navigationShell.currentIndex;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      child: AnimatedBuilder(
        animation: _searchProgress,
        builder: (_, _) {
          final p = _searchProgress.value;
          final showSearch = p > 0.5;

          return Row(
            children: [
              // ── 左侧框：Tab 图标 ──
              Expanded(
                child: showSearch
                    ? _leftBoxCollapsed(cs)
                    : _leftBoxExpanded(cs, tabs, cur),
              ),
              const SizedBox(width: 8),
              // ── 右侧框：搜索 ──
              showSearch
                  ? _rightBoxExpanded(cs)
                  : _rightBoxCollapsed(cs),
            ],
          );
        },
      ),
    );
  }

  // ── 左侧框：正常（三个 Tab） ──
  Widget _leftBoxExpanded(ColorScheme cs, List<AppTab> tabs, int cur) {
    final isDark = cs.brightness == Brightness.dark;
    return _GlassBox(
      isDark: isDark,
      child: SizedBox(
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < tabs.length; i++)
              _TabItem(
                tab: tabs[i],
                selected: i == cur,
                colorScheme: cs,
                onTap: () => _onTab(i),
              ),
          ],
        ),
      ),
    );
  }

  // ── 左侧框：搜索展开状态（仅主页图标） ──
  Widget _leftBoxCollapsed(ColorScheme cs) {
    final p = _searchProgress.value;
    // 宽度随搜索进度收缩：1.0 → 0.45（按整体比例）
    final scale = 1.0 - ((p - 0.5) / 0.5).clamp(0.0, 0.55);

    return FractionallySizedBox(
      widthFactor: scale.clamp(0.45, 1.0),
      child: _GlassBox(
        isDark: cs.brightness == Brightness.dark,
        child: SizedBox(
          height: 56,
          child: Center(
            child: AppTab.home.buildIcon(
              isSelected: widget.navigationShell.currentIndex == 0,
              colorScheme: cs,
            ),
          ),
        ),
      ),
    );
  }

  // ── 右侧框：正常状态（搜索按钮） ──
  Widget _rightBoxCollapsed(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return _GlassBox(
      isDark: isDark,
      child: SizedBox(
        width: 56,
        height: 72,
        child: GestureDetector(
          onTap: _toggleSearch,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Icon(Icons.search_rounded, size: 24,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.7)),
          ),
        ),
      ),
    );
  }

  // ── 右侧框：搜索展开状态（输入框） ──
  Widget _rightBoxExpanded(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return Expanded(
      child: _GlassBox(
        isDark: isDark,
        child: SizedBox(
          height: 56,
          child: _SearchField(
            progress: _searchProgress.value,
            controller: _searchCtrl,
            focusNode: _searchFocus,
            colorScheme: cs,
            onClose: _toggleSearch,
            onSubmit: (_) {
              debugPrint('搜索: ${_searchCtrl.text}');
              _searchFocus.unfocus();
            },
          ),
        ),
      ),
    );
  }
}

// ── 子组件 ──────────────────────────────────────

/// Tab 项：图标 + 文字
class _TabItem extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  const _TabItem({required this.tab, required this.selected, required this.colorScheme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final labelColor = selected
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.35));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.85))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tab.buildIcon(isSelected: selected, colorScheme: colorScheme),
            const SizedBox(height: 2),
            Text(tab.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索输入框（展开时）
class _SearchField extends StatefulWidget {
  final double progress;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ColorScheme colorScheme;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmit;
  const _SearchField({required this.progress, required this.controller, required this.focusNode, required this.colorScheme, required this.onClose, required this.onSubmit});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  Widget build(BuildContext context) {
    final opacity = ((widget.progress - 0.5) / 0.4).clamp(0.0, 1.0);
    final isDark = widget.colorScheme.brightness == Brightness.dark;

    return Row(
      children: [
        const SizedBox(width: 12),
        Expanded(
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  hintText: '搜索书籍或作者…',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.35),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.06),
                  suffixIcon: widget.controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            widget.controller.clear();
                            widget.onSubmit('');
                          },
                          child: Icon(Icons.close_rounded, size: 18,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : Colors.black.withValues(alpha: 0.5)),
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => widget.onSubmit(widget.controller.text),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: widget.onClose,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44,
            alignment: Alignment.center,
            child: Icon(Icons.arrow_back_rounded, size: 22,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.7)),
          ),
        ),
      ],
    );
  }
}

// 模糊效果
final _lightBlur = ImageFilter.blur(sigmaX: 24, sigmaY: 24);
final _darkBlur = ImageFilter.blur(sigmaX: 24, sigmaY: 24);