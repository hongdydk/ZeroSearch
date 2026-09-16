import 'package:flutter_test/flutter_test.dart';
import 'package:shopping_mall/core/network/api_exception.dart';

void main() {
  test('401 and 404 use combined credentials copy', () {
    expect(
      visibleLoginError(ApiException('Not Found', statusCode: 404)),
      loginCredentialsMessage,
    );
    expect(
      visibleLoginError(ApiException('로그인 실패', statusCode: 401)),
      loginCredentialsMessage,
    );
    expect(
      isLoginCredentialsFailure(ApiException('x', statusCode: 401)),
      isTrue,
    );
  });

  test('admin 403 keeps portal copy', () {
    const message = '관리자 계정이 아닙니다.';
    final error = ApiException(message, statusCode: 403);
    expect(visibleLoginError(error), message);
    expect(isLoginCredentialsFailure(error), isFalse);
  });

  test('network errors stay specific', () {
    final timeout = ApiException('요청 시간이 초과되었습니다. 잠시 후 다시 시도하세요.');
    final offline = ApiException('연결할 수 없습니다.');
    expect(visibleLoginError(timeout), timeout.message);
    expect(visibleLoginError(offline), offline.message);
    expect(isLoginCredentialsFailure(timeout), isFalse);
  });
}
