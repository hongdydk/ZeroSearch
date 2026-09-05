import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/login_portal.dart';
import '../providers/app_providers.dart';
import 'safe_next_path.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/auth/buyer_auth_gate.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/portal_auth_gate.dart';
import '../../features/auth/register_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/membership/membership_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/product_detail/catalog_detail_screen.dart';
import '../../features/product_detail/product_detail_screen.dart';
import '../../features/seller/seller_orders_screen.dart';
import '../../features/seller/seller_products_screen.dart';
import '../../features/seller/seller_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../shared/widgets/portal_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  // push('/?major=') 등이 브라우저 주소에 반영되어야 Browse 히스토리가 동작한다.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      // bootstrap 중에는 미로그인으로 취급하지 않음 (로그인 flash 방지).
      if (auth.isLoading) return null;

      final loggedIn = auth.valueOrNull?.isLoggedIn ?? false;
      final portal = auth.valueOrNull?.portal ?? LoginPortal.buyer;
      final path = state.matchedLocation;

      // 판매자·관리자 포털은 경로를 유지하고 PortalAuthGate에서 로그인 UI를 띄운다.
      if (path.startsWith('/seller') || path.startsWith('/admin')) {
        return null;
      }

      final isAuthRoute = path == '/login' || path == '/register';
      if (!loggedIn && _requiresAuth(path)) {
        final raw = state.uri.hasQuery
            ? '${state.matchedLocation}?${state.uri.query}'
            : state.matchedLocation;
        return '/login?next=${Uri.encodeQueryComponent(raw)}';
      }
      if (loggedIn && portal == LoginPortal.buyer && isAuthRoute) {
        return safeNextPath(state.uri.queryParameters['next']) ?? '/';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AdaptiveShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CatalogScreen()),
          GoRoute(
            path: '/catalog/:id',
            builder: (_, state) => CatalogDetailScreen(
              catalogId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (_, state) => ProductDetailScreen(
              productId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/cart',
            builder: (_, _) => const BuyerAuthGate(child: CartScreen()),
          ),
          GoRoute(
            path: '/orders',
            builder: (_, _) => const BuyerAuthGate(child: OrdersScreen()),
          ),
          GoRoute(
            path: '/membership',
            builder: (_, _) => const BuyerAuthGate(child: MembershipScreen()),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const BuyerAuthGate(child: SettingsScreen()),
          ),
          GoRoute(
            path: '/login',
            builder: (_, state) => LoginScreen(
              portal: LoginPortal.buyer,
              next: state.uri.queryParameters['next'],
            ),
          ),
          GoRoute(
            path: '/register',
            builder: (_, state) => RegisterScreen(
              next: state.uri.queryParameters['next'],
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => PortalShell(
          title: '판매자 센터',
          homePath: '/seller',
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/seller',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: SellerScreen(),
            ),
          ),
          GoRoute(
            path: '/seller/products',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: SellerProductsScreen(),
            ),
          ),
          GoRoute(
            path: '/seller/orders',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: SellerOrdersScreen(),
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => PortalShell(
          title: '관리자',
          homePath: '/admin',
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

bool _requiresAuth(String path) {
  if (path == '/') return false;
  if (path.startsWith('/products/')) return false;
  if (path.startsWith('/catalog/')) return false;
  if (path.startsWith('/login') || path.startsWith('/register')) return false;
  if (path.startsWith('/seller') || path.startsWith('/admin')) return false;
  return true;
}

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthState>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

bool isSlimRoute(String location) => false;

bool showPrimaryFab(String location) => false;
