import 'safe_next_path.dart';

/// 구매자 로그인 위치. 이미 `next`가 있으면 유지하고, 아니면 현재 경로를 복귀 URL로 둔다.
String buyerLoginLocation(Uri location) {
  if (location.path == '/login' || location.path == '/register') {
    return _loginWithNext(safeNextPath(location.queryParameters['next']));
  }
  final relative = location.hasQuery
      ? '${location.path}?${location.query}'
      : (location.path.isEmpty ? '/' : location.path);
  return _loginWithNext(safeNextPath(relative));
}

String _loginWithNext(String? next) {
  if (next == null || next.isEmpty) return '/login';
  return Uri(path: '/login', queryParameters: {'next': next}).toString();
}
