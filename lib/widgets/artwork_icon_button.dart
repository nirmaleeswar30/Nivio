import 'package:flutter/material.dart';
import 'package:nivio/widgets/dpad_focusable.dart';

class ArtworkIconButton extends StatefulWidget {
  const ArtworkIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<ArtworkIconButton> createState() => _ArtworkIconButtonState();
}

class _ArtworkIconButtonState extends State<ArtworkIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final button = DpadFocusable(
      borderRadius: BorderRadius.circular(999),
      onActivate: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? const Color(0x4DFFFFFF)
                  : const Color(0x26FFFFFF),
              border: Border.all(
                color: _isHovered
                    ? const Color(0x66FFFFFF)
                    : const Color(0x33FFFFFF),
              ),
            ),
            child: Center(child: widget.icon),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return Semantics(
      button: true,
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}
