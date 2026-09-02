import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';

/// 목업(report/mockup) 헤더 — brand · 검색 · 장바구니 · 로그인 · ≡
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

    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, compact ? 10 : 14, hPad, compact ? 10 : 14),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopRow(auth: auth, isAdmin: isAdmin, showSearch: false),
                      if (_isHome) ...[
                        const SizedBox(height: 10),
                        _CatalogSearchField(
                          value: ref.watch(catalogSearchProvider),
                          onChanged: (v) => ref.read(catalogSearchProvider.notifier).state = v,
                        ),
                      ],
                    ],
                  )
                : _TopRow(
                    auth: auth,
                    isAdmin: isAdmin,
                    showSearch: _isHome,
                    search: _isHome
                        ? _CatalogSearchField(
                            value: ref.watch(catalogSearchProvider),
                            onChanged: (v) =>
                                ref.read(catalogSearchProvider.notifier).state = v,
                          )
                        : null,
                  ),
          ),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ],
      ),
    );
  }
}

class _TopRow extends ConsumerWidget {
  const _TopRow({
    required this.auth,
    required this.isAdmin,
    required this.showSearch,
    this.search,
  });

  final AuthState? auth;
  final bool isAdmin;
  final bool showSearch;
  final Widget? search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _BrandBlock(onBrandTap: () => context.go('/')),
        if (showSearch && search != null) ...[
          const SizedBox(width: 12),
          Expanded(child: search!),
        ] else
          const Spacer(),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => context.go('/cart'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF6B7280),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('장바구니'),
        ),
        _AuthBlock(auth: auth),
        const SizedBox(width: 4),
        _ServicesMenu(auth: auth, isAdmin: isAdmin),
      ],
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
      borderRadius: BorderRadius.circular(4),
      child: Text(
        '제로 서치',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _CatalogSearchField extends StatefulWidget {
  const _CatalogSearchField({
    required this.value,
    required this.onChanged,
  });

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
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: '상품명·카테고리 검색',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: widget.onChanged,
            onSubmitted: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => widget.onChanged(_controller.text),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('검색'),
        ),
      ],
    );
  }
}

class _AuthBlock extends ConsumerWidget {
  const _AuthBlock({required this.auth});

  final AuthState? auth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (auth?.isLoggedIn != true) {
      return TextButton(
        onPressed: () => context.go('/login'),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6B7280),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: const Text('로그인'),
      );
    }

    return _LoggedInBlock(auth: auth);
  }
}

class _LoggedInBlock extends StatelessWidget {
  const _LoggedInBlock({required this.auth});

  final AuthState? auth;

  @override
  Widget build(BuildContext context) {
    final label = auth?.user?.displayName?.trim().isNotEmpty == true
        ? auth!.user!.displayName!
        : 'MY';
    return TextButton(
      onPressed: () => context.go('/settings'),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF6B7280),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
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
        child: Text('≡', style: TextStyle(fontSize: 18, color: Color(0xFF6B7280))),
      ),
    );
  }
}
