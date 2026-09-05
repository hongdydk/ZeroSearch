/// Login `next` — relative path only (`/` start, no `//`).
String? safeNextPath(String? raw) {
  if (raw == null) return null;
  final path = raw.trim();
  if (path.isEmpty || !path.startsWith('/') || path.startsWith('//')) {
    return null;
  }
  return path;
}
