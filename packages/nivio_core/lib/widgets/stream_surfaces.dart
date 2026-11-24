import 'package:flutter/material.dart';
import 'package:nivio/core/theme.dart';

class StreamPanel extends StatelessWidget {
  const StreamPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    return Material(
      color: Color.alphaBlend(
        palette.textPrimary.withValues(alpha: .035),
        palette.background.withValues(alpha: .84),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: palette.border.withValues(alpha: palette.border.a * .70),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme.merge(
        titleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        iconColor: palette.textSecondary,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

class StreamGlyph extends StatelessWidget {
  const StreamGlyph(
    this.icon, {
    super.key,
    this.active = false,
    this.size = 36,
  });

  final IconData icon;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final color = active ? palette.primary : palette.textSecondary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? .16 : .09),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * .48, color: color),
    );
  }
}

class StreamSectionLabel extends StatelessWidget {
  const StreamSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: NivioTheme.themeColorsOf(context).textSecondary,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );
}
