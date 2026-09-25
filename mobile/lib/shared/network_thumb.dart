import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../features/menu/menu_provider.dart';

/// Square thumbnail of a server-hosted photo (dish or receipt), with a
/// placeholder while missing/failing. [path] is the API's `imagePath`.
class NetworkThumb extends ConsumerWidget {
  const NetworkThumb({super.key, required this.path, this.size = 48, this.icon = Icons.restaurant});

  final String? path;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, size: size * 0.5),
    );
    if (path == null || path!.isEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: placeholder);
    }
    final stamp = ref.watch(imageStampProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        '${AppConfig.imageUrl(path!)}?v=$stamp',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
