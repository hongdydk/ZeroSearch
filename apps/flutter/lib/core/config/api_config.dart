class ApiConfig {
  static const String _rawBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );

  /// `--dart-define=API_BASE_URL=.../` 처럼 끝 `/`가 붙으면 Dio가 `//auth/login` URL을 만든다.
  static String get baseUrl => normalizeBaseUrl(_rawBaseUrl);

  static String normalizeBaseUrl(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  static const Duration defaultTimeout = Duration(seconds: 60);
}
