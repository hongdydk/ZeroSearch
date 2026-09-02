import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/auth/login_screen.dart';
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

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final loggedIn = auth.valueOrNull?.isLoggedIn ?? false;
      final path = state.matchedLocation;
      final isAuthRoute = path == '/login' || path == '/register';
      if (!loggedIn && _requiresAuth(path)) return '/login';
      if (loggedIn && isAuthRoute) return '/';
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
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          GoRoute(path: '/membership', builder: (_, _) => const MembershipScreen()),
          GoRoute(path: '/seller', builder: (_, _) => const SellerScreen()),
          GoRoute(path: '/seller/products', builder: (_, _) => const SellerProductsScreen()),
          GoRoute(path: '/seller/orders', builder: (_, _) => const SellerOrdersScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
          GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
          GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
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
  if (path.startsWith('/seller')) return true;
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

