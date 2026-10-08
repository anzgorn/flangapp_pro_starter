import 'package:flutter/material.dart';

import '../models/app_config.dart';
import '../services/hex_color.dart';

/// Colours of the native screens, taken from the app's own settings (the same
/// top bar colour, title colour and accent as the website app).
class NativeColors {
  final Color bar;
  final Color onBar;
  final Color accent;

  NativeColors(this.bar, this.onBar, this.accent);

  factory NativeColors.of(AppConfig config) {
    Color parse(String hex, Color fallback) {
      try {
        return HexColor.fromHex(hex);
      } catch (_) {
        return fallback;
      }
    }

    final bar = parse(config.color, Colors.white);
    return NativeColors(bar, config.isDark ? Colors.white : Colors.black, parse(config.activeColor, Colors.blue));
  }

  ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      // White surfaces: the seed would tint bars and chips with the accent.
      colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: accent, surface: Colors.white,
          surfaceContainerLow: Colors.white, surfaceContainer: Colors.white),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: Colors.black26,
        indicatorColor: accent.withValues(alpha: 0.12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: accent.withValues(alpha: 0.14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bar,
        foregroundColor: onBar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      scaffoldBackgroundColor: Colors.white,
    );
  }
}

class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.grey.shade100,
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400),
    );
    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: Colors.grey.shade100),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class ErrorView extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.retryLabel, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const EmptyView({super.key, required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// A count badge over an icon (cart).
class BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const BadgeIcon({super.key, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }
}
