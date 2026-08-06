import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Displays the image behind an entry's storage path.
///
/// The bucket is private, so this resolves a signed URL through [AppState]
/// (which caches it) and then loads it. While resolving or on any failure it
/// shows [fallback], so a broken or missing image never leaves a hole.
class EntryImage extends StatelessWidget {
  final String? imagePath;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Widget fallback;

  const EntryImage({
    super.key,
    required this.imagePath,
    required this.fallback,
    this.width = double.infinity,
    this.height = 180,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path == null) return fallback;

    return ClipRRect(
      borderRadius: borderRadius,
      child: FutureBuilder<String?>(
        future: context.read<AppState>().imageUrl(path),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _box(context, const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ));
          }
          final url = snap.data;
          if (url == null) return fallback;

          return Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _box(context, const SizedBox()),
            errorBuilder: (_, __, ___) => fallback,
          );
        },
      ),
    );
  }

  Widget _box(BuildContext context, Widget child) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      );
}
