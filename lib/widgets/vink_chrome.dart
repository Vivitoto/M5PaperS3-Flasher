import 'package:flutter/material.dart';

class VinkColors {
  static const ink = Color(0xFF06080D);
  static const ink2 = Color(0xFF0B1020);
  static const surface = Color(0xFF101722);
  static const surfaceHigh = Color(0xFF172033);
  static const line = Color(0xFF263244);
  static const lineSoft = Color(0x1FFFFFFF);
  static const text = Color(0xFFF4F7FB);
  static const muted = Color(0xFF9AA7B6);
  static const cyan = Color(0xFF7DD3FC);
  static const mint = Color(0xFF86EFAC);
  static const amber = Color(0xFFFBBF24);
}

class VinkBackdrop extends StatelessWidget {
  const VinkBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // Keep the app background intentionally flat and even. The previous
        // clipped radial glows produced visible bright/dark patches on real
        // devices and in screenshots, especially behind the firmware library.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1020), Color(0xFF080D16), VinkColors.ink],
          stops: [0, 0.58, 1],
        ),
      ),
      child: child,
    );
  }
}

class VinkHeroHeader extends StatelessWidget {
  const VinkHeroHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.bolt_rounded,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF19243A), Color(0xFF0F1725)],
        ),
        border: Border.all(color: VinkColors.lineSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [VinkColors.cyan, VinkColors.mint],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x337DD3FC),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.black, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: VinkColors.cyan,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: VinkColors.text,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: VinkColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class VinkGlassCard extends StatelessWidget {
  const VinkGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFF1D2B44), Color(0xFF122033)]
              : const [Color(0xFF111927), Color(0xFF0D1320)],
        ),
        border: Border.all(
          color: selected ? const Color(0x667DD3FC) : VinkColors.lineSoft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class VinkPill extends StatelessWidget {
  const VinkPill({
    super.key,
    required this.icon,
    required this.text,
    this.color = VinkColors.cyan,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
