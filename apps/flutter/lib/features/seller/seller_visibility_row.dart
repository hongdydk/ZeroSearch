import 'package:flutter/material.dart';

class SellerVisibilityRow extends StatelessWidget {
  const SellerVisibilityRow({
    super.key,
    required this.isPublic,
    this.onChanged,
  });

  final bool isPublic;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('가시성', style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(),
          Switch(value: isPublic, onChanged: onChanged),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(isPublic ? '공개' : '비공개'),
          ),
        ],
      ),
    );
  }
}
