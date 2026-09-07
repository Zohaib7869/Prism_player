import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

/// Shimmering placeholder grid/list shown while the library scan is running.
class SkeletonLoader extends StatelessWidget {
  final int itemCount;
  final bool grid;
  const SkeletonLoader({super.key, this.itemCount = 6, this.grid = true});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Shimmer.fromColors(
      baseColor: palette.surface,
      highlightColor: palette.surfaceElevated,
      child: grid
          ? GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.3,
              ),
              itemCount: itemCount,
              itemBuilder: (_, __) => Container(
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => Container(
                height: 64,
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14)),
              ),
            ),
    );
  }
}
