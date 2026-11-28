import 'package:flutter/material.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/widgets/dpad_focusable.dart';

class ShelfMoreButton extends StatelessWidget {
  const ShelfMoreButton({
    super.key,
    required this.onPressed,
    this.label = 'More',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = NivioTheme.accentColorOf(context);
    return FocusableInkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios_rounded, size: 11, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
