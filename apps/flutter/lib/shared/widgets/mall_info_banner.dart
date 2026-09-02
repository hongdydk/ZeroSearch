import 'package:flutter/material.dart';

/// 목업 `.note` — 검색·상세 안내 배너.
class MallInfoBanner extends StatelessWidget {
  const MallInfoBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: Color(0xFF1E40AF),
        ),
      ),
    );
  }
}
