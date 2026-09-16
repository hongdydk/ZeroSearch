/// Login `next` — relative path only (`/` start, no `//`).
String? safeNextPath(String? raw) {
  if (raw == null) return null;
  final path = raw.trim();
  if (path.isEmpty || !path.startsWith('/') || path.startsWith('//')) {
    return null;
  }
  return path;
}

/// 예전 게스트 담기 쿼리(`addOffer`/`addQty`)가 남은 `next`를 정리한다.
String? stripPendingCartQuery(String? path) {
  final safe = safeNextPath(path);
  if (safe == null) return null;
  final uri = Uri.parse(safe);
  final q = Map<String, String>.from(uri.queryParameters)
    ..remove('addOffer')
    ..remove('addQty');
  if (q.isEmpty) return uri.path;
  return Uri(path: uri.path, queryParameters: q).toString();
}
