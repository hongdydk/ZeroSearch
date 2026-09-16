import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/auth/login_portal.dart';
import 'package:shopping_mall/core/models/models.dart';
import 'package:shopping_mall/core/providers/app_providers.dart';

void main() {
  final adminUser = UserModel(
    id: 'u1',
    email: 'admin@mall.local',
    isAdmin: true,
  );
  final buyerUser = UserModel(
    id: 'u2',
    email: 'buyer@mall.local',
  );

  test('buyer session does not open /admin even if user is admin', () {
    final session = AuthState(
      buyer: PortalSession(token: 'tok', user: adminUser),
    );
    expect(session.canAccess(LoginPortal.admin), isFalse);
    expect(session.isMallBuyer, isTrue);
    expect(session.isPortal(LoginPortal.admin), isFalse);
  });

  test('non-admin buyer cannot open /admin', () {
    final session = AuthState(
      buyer: PortalSession(token: 'tok', user: buyerUser),
    );
    expect(session.canAccess(LoginPortal.admin), isFalse);
  });

  test('admin portal session can open /admin', () {
    final session = AuthState(
      admin: PortalSession(token: 'tok', user: adminUser),
      active: LoginPortal.admin,
    );
    expect(session.canAccess(LoginPortal.admin), isTrue);
  });

  test('admin portal JWT is not a mall buyer session', () {
    final session = AuthState(
      admin: PortalSession(token: 'tok', user: adminUser),
      active: LoginPortal.admin,
    );
    expect(session.isMallBuyer, isFalse);
    expect(session.isPortal(LoginPortal.admin), isTrue);
    expect(session.isLoggedIn, isTrue);
  });

  test('seller portal JWT is not a mall buyer session', () {
    final session = AuthState(
      seller: PortalSession(token: 'tok', user: buyerUser),
      active: LoginPortal.seller,
    );
    expect(session.isMallBuyer, isFalse);
  });

  test('buyer and admin slots stay independent', () {
    final session = AuthState(
      buyer: PortalSession(token: 'buyer-tok', user: adminUser),
      admin: PortalSession(token: 'admin-tok', user: adminUser),
      active: LoginPortal.buyer,
    );
    expect(session.isMallBuyer, isTrue);
    expect(session.canAccess(LoginPortal.admin), isTrue);
    expect(session.withActive(LoginPortal.admin).token, 'admin-tok');
    expect(session.token, 'buyer-tok');
  });
}
