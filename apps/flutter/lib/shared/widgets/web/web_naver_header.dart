import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/ui_platform.dart';
import '../../../core/providers/app_providers.dart';

/// 쇼핑몰 웹 글로벌 헤더.
class WebNaverHeader extends ConsumerWidget {
  const WebNaverHeader({
    super.key,
    required this.location,
    required this.isAdmin,
    this.compact = false,
  });

  final String location;
  final bool isAdmin;
  final bool compact;

  bool get _isHome => location == '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final theme = Theme.of(context);
    final hPad = compact ? 12.0 : 20.0;
    final maxWidth = compact ? double.infinity : webContentMaxWidth;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, compact ? 8 : 12, hPad, compact ? 8 : 10),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _BrandBlock(onBrandTap: () => context.go('/'))),
                              IconButton(
                                tooltip: '장바구니',
                                onPressed: () => context.go('/cart'),
                                icon: const Icon(Icons.shopping_cart_outlined),
                              ),
                              _AuthBlock(auth: auth),
                              const SizedBox(width: 4),
                              _ServicesMenu(auth: auth, isAdmin: isAdmin),
                            ],
                          ),
                          if (_isHome) ...[
                            const SizedBox(height: 8),
                            _CatalogSearchField(
                              compact: true,
                              value: ref.watch(catalogSearchProvider),
                              onChanged: (v) =>
                                  ref.read(catalogSearchProvider.notifier).state = v,
                            ),
                          ],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _BrandBlock(onBrandTap: () => context.go('/')),
                          const Spacer(),
                          if (_isHome) ...[
                            SizedBox(
                              width: 360,
                              child: _CatalogSearchField(
                                compact: false,
                                value: ref.watch(catalogSearchProvider),
                                onChanged: (v) =>
                                    ref.read(catalogSearchProvider.notifier).state = v,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          IconButton(
                            tooltip: '장바구니',
                            onPressed: () => context.go('/cart'),
                            icon: const Icon(Icons.shopping_cart_outlined),
                          ),
                          _AuthBlock(auth: auth),
                          const SizedBox(width: 4),
                          _ServicesMenu(auth: auth, isAdmin: isAdmin),
                        ],
                      ),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ],
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.onBrandTap});

  final VoidCallback onBrandTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onBrandTap,
      child: Text(
        'Shopping Mall',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _CatalogSearchField extends StatefulWidget {
  const _CatalogSearchField({
    required this.compact,
    required this.value,
    required this.onChanged,
  });

  final bool compact;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends State<_CatalogSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CatalogSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: '상품명·카테고리 검색',
        prefixIcon: Icon(Icons.search, size: widget.compact ? 18 : 20),
        contentPadding: EdgeInsets.symmetric(vertical: widget.compact ? 8 : 10),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(2),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _AuthBlock extends ConsumerWidget {
  const _AuthBlock({required this.auth});

  final AuthState? auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (auth?.isLoggedIn != true) {
      return OutlinedButton(
        onPressed: () => context.go('/login'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        child: const Text('로그인'),
      );
    }

    return _CreditChip(onTap: () => _showCredits(context));
  }

  void _showCredits(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('크레딧'),
        content: const Text('실결제·충전은 아직 지원하지 않습니다. (스텁)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }
}

class _ServicesMenu extends ConsumerWidget {
  const _ServicesMenu({required this.auth, required this.isAdmin});

  final AuthState? auth;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: '전체 메뉴',
      onSelected: (value) {
        if (value == 'logout') {
          ref.read(authStateProvider.notifier).logout();
        } else {
          context.go(value);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: '/orders', child: Text('주문')),
        const PopupMenuItem(value: '/membership', child: Text('멤버십')),
        const PopupMenuItem(value: '/seller', child: Text('판매자 센터')),
        const PopupMenuItem(value: '/settings', child: Text('설정')),
        if (isAdmin) const PopupMenuItem(value: '/admin', child: Text('관리자')),
        if (auth?.isLoggedIn == true)
          const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.apps),
      ),
    );
  }
}

class _CreditChip extends ConsumerWidget {
  const _CreditChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditsProvider);
    final balance = credits.valueOrNull;
    return TextButton(
      onPressed: onTap,
      child: Text('💎 ${balance?.toString() ?? '…'}'),
    );
  }
}
