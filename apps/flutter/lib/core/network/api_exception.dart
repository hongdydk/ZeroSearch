class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.detail});

  final String message;
  final int? statusCode;
  final Object? detail;

  @override
  String toString() => message;
}
