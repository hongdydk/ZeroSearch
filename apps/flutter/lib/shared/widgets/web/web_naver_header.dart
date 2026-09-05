import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/catalog/browse_location.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';

/// 목업(report/mockup) 헤더 — brand · 검색 · 장바구니 · 로그인 · ≡
class WebNaverHeader extends ConsumerWidget {
  const WebNaverHeader({
    super.key,
    required this.location,
    this.compact = false,
  });

  final String location;
  final bool compact;

  bool get _isHome => location == '/';

  static const _onTealMuted = Color(0xFFD5E2E0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final hPad = compact ? 12.0 : 20.0;

    return ColoredBox(
      color: AppTheme.brandTeal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, compact ? 10 : 14, hPad, compact ? 10 : 14),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopRow(auth: auth, showSearch: false),
                      if (_isHome) ...[
                        const SizedBox(height: 10),
                        _CatalogSearchField(value: ref.watch(catalogSearchProvider)),
                      ],
                    ],
                  )
                : _TopRow(
                    auth: auth,
                    showSearch: _isHome,
                    search: _isHome
                        ? _CatalogSearchField(value: ref.watch(catalogSearchProvider))
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopRow extends ConsumerWidget {
  const _TopRow({
    required this.auth,
    required this.showSearch,
    this.search,
  });

  final AuthState? auth;
  final bool showSearch;
  final Widget? search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _BrandBlock(onBrandTap: () {
          clearCatalogBrowse(ref);
          context.go('/');
        }),
        if (showSearch && search != null) ...[
          const SizedBox(width: 12),
          Expanded(child: search!),
        ] else
          const Spacer(),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => context.go('/cart'),
          style: TextButton.styleFrom(
            foregroundColor: WebNaverHeader._onTealMuted,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('장바구니'),
        ),
        _AuthBlock(auth: auth),
        const SizedBox(width: 4),
        _ServicesMenu(auth: auth),
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
      child: const Text(
        '제로 서치',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _CatalogSearchField extends ConsumerStatefulWidget {
  const _CatalogSearchField({required this.value});

  final String value;

  @override
  ConsumerState<_CatalogSearchField> createState() => _CatalogSearchFieldState();
}

class _CatalogSearchFieldState extends ConsumerState<_CatalogSearchField> {
  late final TextEditingController _controller;
  final _debounce = CatalogSearchDebounce();

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
    _debounce.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit(String value) {
    ref.read(catalogSearchProvider.notifier).state = value;
    _debounce.schedule(value, (committed) {
      if (!mounted) return;
      final q = committed.trim();
      context.go(q.isEmpty ? '/' : browseLocation(q: q));
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: '밥, 떡, 쌀…',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
        prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.85), size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.14),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(999),
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      onChanged: _commit,
      onSubmitted: (v) {
        _debounce.cancel();
        ref.read(catalogSearchProvider.notifier).state = v;
        final q = v.trim();
        context.go(q.isEmpty ? '/' : browseLocation(q: q));
      },
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
          foregroundColor: WebNaverHeader._onTealMuted,
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
        foregroundColor: WebNaverHeader._onTealMuted,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
    );
  }
}

class _ServicesMenu extends ConsumerWidget {
  const _ServicesMenu({required this.auth});

  final AuthState? auth;

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
        const PopupMenuItem(value: '/settings', child: Text('설정')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '/seller', child: Text('판매자 센터')),
        const PopupMenuItem(value: '/admin', child: Text('관리자')),
        if (auth?.isLoggedIn == true)
          const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Text('≡', style: TextStyle(fontSize: 18, color: Color(0xFFD5E2E0))),
      ),
    );
  }
}
