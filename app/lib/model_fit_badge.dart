import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

/// Colour for a fit rating: green optimal, yellow possible, red not
/// recommended, grey unknown.
Color fitColor(ModelFitRating rating) => switch (rating) {
      ModelFitRating.optimal => fitOptimalColor,
      ModelFitRating.possible => fitPossibleColor,
      ModelFitRating.notRecommended => fitNotRecommendedColor,
      ModelFitRating.unknown => fitUnknownColor,
    };

/// Compact "will it run here?" chip for a model card.
///
/// Colour is never the only signal — the rating's text label rides along with
/// it, and the backend's one-line explanation is the tooltip.
class ModelFitBadge extends StatelessWidget {
  const ModelFitBadge({super.key, required this.fit, this.compact = false});

  final ModelFit fit;

  /// Dot-and-label only, for the dense model list. The full form adds an icon
  /// and more padding, for the detail page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = fitColor(fit.rating);
    return Tooltip(
      message: fit.reason,
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // A tint of the rating colour rather than the colour itself: a solid
          // red pill on every oversized model would shout louder than these
          // cards should.
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 6 : 7,
              height: compact ? 6 : 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: compact ? 5 : 6),
            Text(
              compact ? fit.rating.shortLabel : fit.rating.label,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: compact ? 10 : 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
