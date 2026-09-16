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
}
