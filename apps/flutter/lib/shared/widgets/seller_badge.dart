import 'package:flutter/material.dart';

class SellerBadge extends StatelessWidget {
  const SellerBadge({super.key, required this.shopName, required this.isOfficial});

  final String shopName;
  final bool isOfficial;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          shopName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (isOfficial)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '공식',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}
