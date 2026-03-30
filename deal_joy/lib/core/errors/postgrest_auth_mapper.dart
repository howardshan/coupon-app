// PostgREST 错误中与「会话/JWT」相关的识别，避免误报为「数据不存在」

import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_exception.dart';

/// 是否为访问令牌过期、无效 JWT 等鉴权类错误（与券是否存在无关）
bool isPostgrestSessionExpiredLike(PostgrestException e) {
  final m = e.message.toLowerCase().trim();
  if (m.contains('jwt expired')) return true;
  if (m.contains('invalid jwt')) return true;
  if (m.contains('token expired')) return true;
  if (m.contains('session') && m.contains('expired')) return true;
  return false;
}

/// 单张券查询：会话错误 → AppAuth；0 行 → not found；其它 → 通用加载失败
Never throwForCouponDetailPostgrest(PostgrestException e) {
  if (isPostgrestSessionExpiredLike(e)) {
    throw AppAuthException(
      'Your session has expired. Please sign in again, then retry.',
      code: e.code ?? 'session_expired',
    );
  }
  if (e.code == 'PGRST116') {
    throw AppException('Coupon not found.', code: e.code);
  }
  throw AppException(
    'Could not load this coupon. ${e.message}',
    code: e.code,
  );
}

/// 券列表：会话错误 → AppAuth；其它保持原语义
Never throwForCouponListPostgrest(PostgrestException e) {
  if (isPostgrestSessionExpiredLike(e)) {
    throw AppAuthException(
      'Your session has expired. Please sign in again.',
      code: e.code ?? 'session_expired',
    );
  }
  throw AppException('Failed to load coupons: ${e.message}', code: e.code);
}

/// 通用按 id 取 coupon 行（orders 等复用）
Never throwForCouponFetchPostgrest(PostgrestException e) {
  if (isPostgrestSessionExpiredLike(e)) {
    throw AppAuthException(
      'Your session has expired. Please sign in again, then retry.',
      code: e.code ?? 'session_expired',
    );
  }
  if (e.code == 'PGRST116') {
    throw AppException('Coupon not found.', code: e.code);
  }
  throw AppException('Could not load coupon: ${e.message}', code: e.code);
}
