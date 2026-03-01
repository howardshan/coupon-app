class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => 'AppException: $message';
}

class AppAuthException extends AppException {
  const AppAuthException(super.message, {super.code});
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

class PaymentException extends AppException {
  const PaymentException(super.message, {super.code});
}
