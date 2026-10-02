import 'dart:async';
import 'package:flutter/material.dart';

/// 全局导航 key，用于在没有 BuildContext 的服务层弹出顶部横幅
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class _TopBannerData {
  final String message;
  final IconData? icon;
  _TopBannerData(this.message, this.icon);
}

OverlayEntry? _bannerEntry;
Timer? _bannerTimer;
_TopBannerData? _pending;

/// 在屏幕顶部展示一条横幅，[duration] 后自动消失（默认 2 秒）。
///
/// 供“翻译完成”等一次性提示使用：顶部弹出，驻留两秒后消失，
/// 同时该事件会以通知形式存入通知中心，供首页红点提示查看。
///
/// 若当前尚无可用 Overlay（如启动阶段），会暂存最新的消息，
/// 待下一次调用时优先展示，避免丢失提示。
void showTopBanner(
  String message, {
  IconData? icon,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = appNavigatorKey.currentState?.overlay;
  if (overlay == null) {
    _pending = _TopBannerData(message, icon);
    return;
  }

  // 优先展示之前暂存的消息
  _TopBannerData data = _pending ?? _TopBannerData(message, icon);
  _pending = null;
  if (message.isNotEmpty) {
    data = _TopBannerData(message, icon);
  }

  _bannerTimer?.cancel();
  _bannerEntry?.remove();
  _bannerEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TopBannerOverlay(message: data.message, icon: data.icon),
  );
  _bannerEntry = entry;
  overlay.insert(entry);

  var shown = true;
  _bannerTimer = Timer(duration, () {
    if (identical(_bannerEntry, entry) && shown) {
      shown = false;
      _bannerEntry = null;
      if (entry.mounted) entry.remove();
    }
  });
}

/// 顶部横幅 Overlay
class _TopBannerOverlay extends StatelessWidget {
  final String message;
  final IconData? icon;

  const _TopBannerOverlay({required this.message, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -0.6, end: 0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) =>
                  Transform.translate(offset: Offset(0, v * 56), child: child),
              child: Opacity(
                opacity: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.inverseSurface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: cs.onInverseSurface),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onInverseSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}