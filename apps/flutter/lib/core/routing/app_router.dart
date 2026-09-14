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
import '../../features/addresses/address_form_screen.dart';
import '../../features/addresses/address_list_screen.dart';
import '../../features/cart/cart_screen.dart';
import '../../features/checkout/checkout_screen.dart';
import '../../features/catalog/catalog_screen.dart';
import '../../features/membership/membership_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/payment/payment_result_screen.dart';
import '../../features/payment/toss_pay_exit_screen.dart';
import '../../features/product_detail/catalog_detail_screen.dart';
import '../../features/product_detail/product_detail_screen.dart';
import '../../features/seller/seller_orders_screen.dart';
import '../../features/seller/seller_products_screen.dart';
import '../../features/seller/seller_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../shared/widgets/portal_shell.dart';
import '../../shared/widgets/portal_workspace.dart';

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
      GoRoute(
        path: '/toss-pay',
        builder: (_, _) => const TossPayExitScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AdaptiveShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CatalogScreen()),
          GoRoute(
            path: '/catalog/:id',
            builder: (_, state) =>
                CatalogDetailScreen(catalogId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (_, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/cart',
            builder: (_, _) => const BuyerAuthGate(child: CartScreen()),
          ),
          GoRoute(
            path: '/checkout',
            builder: (_, _) => const BuyerAuthGate(child: CheckoutScreen()),
          ),
          GoRoute(
            path: '/orders',
            builder: (_, _) => const BuyerAuthGate(child: OrdersScreen()),
          ),
          GoRoute(
            path: '/payment/success',
            builder: (_, state) => BuyerAuthGate(
              child: PaymentSuccessScreen(
                paymentKey: state.uri.queryParameters['paymentKey'],
                orderId: state.uri.queryParameters['orderId'],
                amount: state.uri.queryParameters['amount'],
              ),
            ),
          ),
          GoRoute(
            path: '/payment/fail',
            builder: (_, state) => BuyerAuthGate(
              child: PaymentFailScreen(
                code: state.uri.queryParameters['code'],
                message: state.uri.queryParameters['message'],
                orderId: state.uri.queryParameters['orderId'],
              ),
            ),
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
            path: '/settings/addresses',
            builder: (_, _) =>
                const BuyerAuthGate(child: AddressListScreen()),
          ),
          GoRoute(
            path: '/settings/addresses/new',
            builder: (_, _) =>
                const BuyerAuthGate(child: AddressFormScreen()),
          ),
          GoRoute(
            path: '/settings/addresses/:id',
            builder: (_, state) => BuyerAuthGate(
              child: AddressFormScreen(addressId: state.pathParameters['id']),
            ),
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
            builder: (_, state) =>
                RegisterScreen(next: state.uri.queryParameters['next']),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PortalShell(title: '판매자 센터', homePath: '/seller', child: child),
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
          GoRoute(
            path: '/seller/stats',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.seller,
                activePath: '/seller/stats',
                title: '통계',
                description: '주문·배송·오퍼 운영 추이를 한곳에서 확인하는 화면입니다.',
                items: ['기간별 주문 줄 추이', '배송 상태 분포', '오퍼 노출·품절 비율'],
              ),
            ),
          ),
          GoRoute(
            path: '/seller/alerts',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.seller,
                activePath: '/seller/alerts',
                title: '알림',
                description: '즉시 확인해야 할 판매 운영 변화를 모아 보는 화면입니다.',
                items: ['신규 주문', '재고 부족·품절', '카탈로그 검수 결과'],
              ),
            ),
          ),
          GoRoute(
            path: '/seller/saved-filters',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.seller,
                activePath: '/seller/saved-filters',
                title: '저장 필터',
                description: '자주 보는 주문·오퍼 조건을 저장하는 화면입니다.',
                items: ['오늘 출고', '재고 5개 이하', '숨김 오퍼'],
              ),
            ),
          ),
          GoRoute(
            path: '/seller/activity',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.seller,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.seller,
                activePath: '/seller/activity',
                title: '작업 기록',
                description: '오퍼와 주문 상태 변경 이력을 확인하는 화면입니다.',
                items: ['가격·재고 변경', '노출 상태 변경', '주문 배송 상태 변경'],
              ),
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PortalShell(title: '관리자', homePath: '/admin', child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.home),
            ),
          ),
          GoRoute(
            path: '/admin/stats',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.stats),
            ),
          ),
          GoRoute(
            path: '/admin/sellers',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.sellers),
            ),
          ),
          GoRoute(
            path: '/admin/orders',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.orders),
            ),
          ),
          GoRoute(
            path: '/admin/catalog',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.catalog),
            ),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.users),
            ),
          ),
          GoRoute(
            path: '/admin/tools',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: AdminScreen(section: AdminSection.tools),
            ),
          ),
          GoRoute(
            path: '/admin/alerts',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.admin,
                activePath: '/admin/alerts',
                title: '알림',
                description: '운영자가 처리할 대기·지연 항목을 모아 보는 화면입니다.',
                items: ['입점 승인 대기', '카탈로그 연결 충돌', '오래 멈춘 주문 줄'],
              ),
            ),
          ),
          GoRoute(
            path: '/admin/saved-filters',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.admin,
                activePath: '/admin/saved-filters',
                title: '저장 필터',
                description: '반복 점검하는 운영 조건을 저장하는 화면입니다.',
                items: ['오래된 승격 대기', '정지 판매자', '공개 오퍼 없는 카드'],
              ),
            ),
          ),
          GoRoute(
            path: '/admin/audit',
            builder: (_, _) => const PortalAuthGate(
              portal: LoginPortal.admin,
              child: PortalComingSoonScreen(
                role: PortalWorkspaceRole.admin,
                activePath: '/admin/audit',
                title: '감사 로그',
                description: '관리자 변경 작업의 주체와 전후 상태를 확인하는 화면입니다.',
                items: ['입점 승인·정지', '카드 연결·승격', '주문 상태 보정'],
              ),
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
  if (path == '/toss-pay') return false;
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
