import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../theme/index.dart';
import '../common/hover_card.dart';

enum ProviderCardVariant { grid, studio }

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.name,
    this.logoImage,
    this.label,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
    this.variant = ProviderCardVariant.grid,
  });

  final String name;
  final ImageProvider? logoImage;
  final String? label;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;
  final ProviderCardVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant == ProviderCardVariant.studio) {
      return _StudioProviderCard(
        name: name,
        logoImage: logoImage,
        semanticLabel: semanticLabel,
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
      );
    }

    return HoverCard(
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel ?? name,
      onTap: onTap,
      borderRadius: AppRadius.medium,
      hoverScale: 1.015,
      padding: EdgeInsets.zero,
      backgroundColor: AppColors.surface.withValues(alpha: 0.82),
      borderColor: AppColors.borderSubtle.withValues(alpha: 0.74),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.045),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logoImage != null
                          ? Image(
                              image: logoImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _ProviderFallback(name: name),
                            )
                          : _ProviderFallback(name: name),
                    ),
                    const Spacer(),
                    Icon(
                      LucideIcons.arrowUpRight,
                      size: 18,
                      color: AppColors.textMuted.withValues(alpha: 0.72),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  style: AppTypography.title.copyWith(fontSize: 15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (label != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label!,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioProviderCard extends StatelessWidget {
  const _StudioProviderCard({
    required this.name,
    required this.logoImage,
    required this.semanticLabel,
    required this.focusNode,
    required this.autofocus,
    required this.onTap,
  });

  final String name;
  final ImageProvider? logoImage;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel ?? name,
      onTap: onTap,
      borderRadius: AppRadius.medium,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      borderColor: Colors.transparent,
      focusBorderColor: Colors.white.withValues(alpha: 0.70),
      hoverScale: 1.035,
      shadow: const [],
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.025),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.12),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.huge,
                    vertical: AppSpacing.xxl,
                  ),
                  child: logoImage != null
                      ? Image(
                          image: logoImage!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _StudioFallback(name: name),
                        )
                      : _StudioFallback(name: name),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioFallback extends StatelessWidget {
  const _StudioFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: AppTypography.sectionTitle.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProviderFallback extends StatelessWidget {
  const _ProviderFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.characters.first,
        style: AppTypography.sectionTitle.copyWith(fontSize: 18),
      ),
    );
  }
}
