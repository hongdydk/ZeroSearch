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
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '가시성',
        contentPadding: EdgeInsets.fromLTRB(12, 4, 8, 4),
      ),
      child: Row(
        children: [
          const Spacer(),
          Switch(value: isPublic, onChanged: onChanged),
          const SizedBox(width: 8),
          Text(isPublic ? '공개' : '비공개'),
        ],
      ),
    );
  }
}
