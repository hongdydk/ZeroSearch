import 'package:flutter/material.dart';

class SellerBadge extends StatelessWidget {
  const SellerBadge({super.key, required this.shopName, required this.isOfficial});

  final String shopName;
  final bool isOfficial;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isOfficial) _Pill(label: '공식', bg: const Color(0xFFCCFBF1), fg: const Color(0xFF0F766E)),
        if (!isOfficial) _Pill(label: '입점', bg: const Color(0xFFEDE9FE), fg: const Color(0xFF7C3AED)),
        Text(
          shopName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontSize: 11,
              ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
