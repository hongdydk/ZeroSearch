import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.imageUrl, required this.title});

  final String? imageUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
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
