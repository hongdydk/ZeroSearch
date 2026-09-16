class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.detail});

  final String message;
  final int? statusCode;
  final Object? detail;

  @override
  String toString() => message;
}

/// 없는 계정·틀린 비밀번호를 구분하지 않는 로그인 실패 문구 (계정 열거 방지).
const loginCredentialsMessage = '이메일 또는 비밀번호가 올바르지 않습니다.';

/// 자격 증명 실패 시 본문 아래 보조 안내. 관리자 포털에서는 쓰지 않는다.
const loginCredentialsHint = '비밀번호를 다시 확인하거나, 계정이 없으면 회원가입을 해 주세요.';

bool isLoginCredentialsFailure(Object error) {
  if (error is! ApiException) return false;
  final code = error.statusCode;
  if (code == 401 || code == 404) return true;
  if (code != null) return false;
  final message = error.message.trim();
  return message == loginCredentialsMessage ||
      message == '로그인 실패' ||
      message == '요청에 실패했습니다.';
}

/// 로그인 폼에 그대로 보여 줄 한 줄. 네트워크·403은 API/클라이언트 문구를 유지한다.
String visibleLoginError(Object error) {
  if (error is ApiException) {
    final code = error.statusCode;
    if (code == 403) return error.message;
    if (isLoginCredentialsFailure(error)) return loginCredentialsMessage;
    final message = error.message.trim();
    if (message.isEmpty || message == '로그인 실패') {
      return loginCredentialsMessage;
    }
    return message;
  }
  return loginCredentialsMessage;
}
