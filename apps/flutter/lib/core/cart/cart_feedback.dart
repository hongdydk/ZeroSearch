import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void showAddedToCartSnackBar(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('장바구니에 담았습니다.'),
      action: SnackBarAction(
        label: '장바구니 보기',
        onPressed: () => router?.go('/cart'),
      ),
    ),
  );
}
