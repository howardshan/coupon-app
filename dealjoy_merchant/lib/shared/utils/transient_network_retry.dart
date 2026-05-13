// 对偶发网络错误做有限次重试（不依赖 dart:io，避免 Flutter Web 编译问题）

/// 判断是否为可重试的瞬时网络类错误（连接被重置、超时、DNS 等）
bool isLikelyTransientNetworkError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('connection reset') ||
      msg.contains('connection closed') ||
      msg.contains('connection aborted') ||
      msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('timed out') ||
      msg.contains('timeoutexception') ||
      (msg.contains('clientexception') &&
          (msg.contains('reset') ||
              msg.contains('closed') ||
              msg.contains('aborted') ||
              msg.contains('timeout') ||
              msg.contains('timed out')));
}

/// 法律文档页等场景：错误主标题（英文 UI，不暴露异常类名）
String userFacingLoadFailureTitle() => 'Unable to load document';

/// 将异常转为面向用户的短英文说明（不含 URL / ClientException 等堆栈）
String userFacingLoadFailureMessage(Object error) {
  if (isLikelyTransientNetworkError(error)) {
    return 'Check your internet connection and tap Retry.';
  }
  final s = error.toString().toLowerCase();
  if (s.contains('jwt') ||
      s.contains('unauthorized') ||
      s.contains(' 401') ||
      s.contains('invalid refresh')) {
    return 'Your session may have expired. Please sign in again and retry.';
  }
  if (s.contains('not found') ||
      s.contains('pgrst116') ||
      s.contains(' 404') ||
      s.contains('no rows')) {
    return 'This document is not available.';
  }
  return 'Something went wrong. Please try again later.';
}

/// 对 [action] 执行最多 [maxAttempts] 次，遇瞬时网络错误则指数退避后重试
Future<T> retryTransientNetwork<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await action();
    } catch (e, st) {
      final canRetry =
          isLikelyTransientNetworkError(e) && attempt < maxAttempts - 1;
      if (!canRetry) {
        Error.throwWithStackTrace(e, st);
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt)));
    }
  }
  throw StateError('retryTransientNetwork: unreachable');
}
