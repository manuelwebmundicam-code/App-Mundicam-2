class MundicamEndpointException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const MundicamEndpointException({
    required this.message,
    this.statusCode,
    this.code = 'mundicam_endpoint_error',
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return '$code$status: $message';
  }
}
