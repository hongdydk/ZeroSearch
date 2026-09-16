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

  test('promoted admin with buyer portal can open /admin', () {
    final session = AuthState(
      user: adminUser,
      token: 'tok',
      portal: LoginPortal.buyer,
    );
    expect(session.canAccess(LoginPortal.admin), isTrue);
    expect(session.isPortal(LoginPortal.admin), isFalse);
  });

  test('non-admin buyer cannot open /admin', () {
    final session = AuthState(
      user: buyerUser,
      token: 'tok',
      portal: LoginPortal.buyer,
    );
    expect(session.canAccess(LoginPortal.admin), isFalse);
  });

  test('admin portal session can open /admin', () {
    final session = AuthState(
      user: adminUser,
      token: 'tok',
      portal: LoginPortal.admin,
    );
    expect(session.canAccess(LoginPortal.admin), isTrue);
  });

  test('admin portal JWT is not a mall buyer session', () {
    final session = AuthState(
      user: adminUser,
      token: 'tok',
      portal: LoginPortal.admin,
    );
    expect(session.isMallBuyer, isFalse);
    expect(session.isPortal(LoginPortal.admin), isTrue);
  });

  test('seller portal JWT is not a mall buyer session', () {
    final session = AuthState(
      user: buyerUser,
      token: 'tok',
      portal: LoginPortal.seller,
    );
    expect(session.isMallBuyer, isFalse);
  });

  test('buyer portal stays a mall buyer even if user is admin', () {
    final session = AuthState(
      user: adminUser,
      token: 'tok',
      portal: LoginPortal.buyer,
    );
    expect(session.isMallBuyer, isTrue);
    expect(session.canAccess(LoginPortal.admin), isTrue);
  });
}
