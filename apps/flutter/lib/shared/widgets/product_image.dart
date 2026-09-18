import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.imageUrl, required this.title});

  final String? imageUrl;
  final String title;

  static String? resolveUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/uploads/')) {
      return '${ApiConfig.baseUrl}$url';
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveUrl(imageUrl);
    if (resolved != null && resolved.isNotEmpty) {
      return Image.network(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.shopping_bag_outlined, color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
