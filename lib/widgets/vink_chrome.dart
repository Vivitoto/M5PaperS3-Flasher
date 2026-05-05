import 'package:flutter/material.dart';

class VinkColors {
  // Monochrome ink-wash palette. Keep the old semantic names so existing UI
  // code still reads naturally, but map them to restrained paper / ink tones.
  static const ink = Color(0xFF050505);
  static const ink2 = Color(0xFF0D0D0C);
  static const surface = Color(0xFF121210);
  static const surfaceHigh = Color(0xFF1B1A17);
  static const surfaceLift = Color(0xFF24221E);
  static const line = Color(0xFF36332D);
  static const lineSoft = Color(0x26F4EFE3);
  static const text = Color(0xFFF4EFE3);
  static const muted = Color(0xFFA9A197);
  static const subtle = Color(0xFF706A61);
  static const cyan = Color(0xFFEDE6D8);
  static const blue = Color(0xFFCFC7BA);
  static const violet = Color(0xFFB7B0A7);
  static const mint = Color(0xFFE6E0D2);
  static const amber = Color(0xFFC8BFAE);
  static const rose = Color(0xFFD0C4BA);
}

class VinkBackdrop extends StatelessWidget {
  const VinkBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF12110F),
                  Color(0xFF090909),
                  Color(0xFF030303),
                ],
                stops: [0, 0.52, 1],
              ),
            ),
          ),
        ),
        const Positioned(
          top: -120,
          right: -110,
          width: 300,
          height: 300,
          child: _InkWash(
            colors: [Color(0x18F4EFE3), Color(0x00F4EFE3)],
          ),
        ),
        const Positioned(
          left: -150,
          bottom: 40,
          width: 360,
          height: 360,
          child: _InkWash(
            colors: [Color(0x14000000), Color(0x00000000)],
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _InkWash extends StatelessWidget {
  const _InkWash({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class VinkHeroHeader extends StatelessWidget {
  const VinkHeroHeader({
    super.key,
    required this.title,
    this.icon = Icons.bolt_rounded,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(14, 12, 13, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEE181715), Color(0xEE0C0C0B)],
        ),
        border: Border.all(color: Color(0x2EF4EFE3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          VinkIconTile(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: VinkColors.text,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.45,
                height: 1.08,
              ),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFF25231F), Color(0xFF171614)]
              : const [Color(0xE8191815), Color(0xE80D0D0B)],
        ),
        border: Border.all(
          color: selected ? const Color(0x70F4EFE3) : VinkColors.lineSoft,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class VinkIconTile extends StatelessWidget {
  const VinkIconTile({
    super.key,
    required this.icon,
    this.large = false,
    this.color = VinkColors.cyan,
  });

  final IconData icon;
  final bool large;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = large ? 46.0 : 38.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(large ? 16 : 13),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4EFE3), Color(0xFFCFC7BA)],
        ),
        border: Border.all(color: const Color(0x55FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.black, size: large ? 25 : 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x10F4EFE3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.06,
            ),
          ),
        ],
      ),
    );
  }
}

class VinkSoftDivider extends StatelessWidget {
  const VinkSoftDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x00F4EFE3), Color(0x26F4EFE3), Color(0x00F4EFE3)],
        ),
      ),
    );
  }
}
