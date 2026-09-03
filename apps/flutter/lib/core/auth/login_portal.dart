enum LoginPortal {
  buyer,
  seller,
  admin;

  static LoginPortal parse(String? value) {
    for (final portal in LoginPortal.values) {
      if (portal.name == value) return portal;
    }
    return LoginPortal.buyer;
  }

  String get loginTitle => switch (this) {
        LoginPortal.buyer => '로그인',
        LoginPortal.seller => '판매자 로그인',
        LoginPortal.admin => '관리자 로그인',
      };

  String get homePath => switch (this) {
        LoginPortal.buyer => '/',
        LoginPortal.seller => '/seller',
        LoginPortal.admin => '/admin',
      };
}
