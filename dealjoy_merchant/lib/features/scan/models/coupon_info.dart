// 团购券核销相关数据模型
// 包含: CouponInfo（券验证信息）、RedemptionRecord（核销历史记录）、ScanError（错误枚举）

/// 扫码验证返回的券信息
class CouponInfo {
  final String id;
  final String code;
  final String dealTitle;
  final String userName; // 脱敏处理后的用户名
  final DateTime validUntil;
  final CouponStatus status;
  final DateTime? redeemedAt;

  const CouponInfo({
    required this.id,
    required this.code,
    required this.dealTitle,
    required this.userName,
    required this.validUntil,
    required this.status,
    this.redeemedAt,
  });

  /// 从 Edge Function 返回的 JSON 构造
  factory CouponInfo.fromJson(Map<String, dynamic> json) {
    return CouponInfo(
      id: json['id'] as String,
      code: json['code'] as String,
      dealTitle: json['deal_title'] as String,
      userName: json['user_name'] as String,
      validUntil: DateTime.parse(json['valid_until'] as String),
      status: CouponStatus.fromString(json['status'] as String),
      redeemedAt: json['redeemed_at'] != null
          ? DateTime.parse(json['redeemed_at'] as String)
          : null,
    );
  }

  /// 是否可以核销（仅 active/unused 状态可核销）
  bool get isRedeemable =>
      status == CouponStatus.active && validUntil.isAfter(DateTime.now());
}

/// 券当前状态枚举
enum CouponStatus {
  active,   // 可核销
  used,     // 已核销
  expired,  // 已过期
  refunded; // 已退款

  factory CouponStatus.fromString(String value) {
    switch (value) {
      case 'active':
      case 'unused': // 兼容旧数据库枚举值
        return CouponStatus.active;
      case 'used':
        return CouponStatus.used;
      case 'expired':
        return CouponStatus.expired;
      case 'refunded':
        return CouponStatus.refunded;
      default:
        return CouponStatus.active;
    }
  }

  String get displayLabel {
    switch (this) {
      case CouponStatus.active:
        return 'Valid';
      case CouponStatus.used:
        return 'Used';
      case CouponStatus.expired:
        return 'Expired';
      case CouponStatus.refunded:
        return 'Refunded';
    }
  }
}

/// 核销历史记录（用于历史列表页）
class RedemptionRecord {
  final String id;
  final String couponId;
  final String couponCode;
  final String dealTitle;
  final String userName; // 脱敏
  final DateTime redeemedAt;
  final bool isReverted;
  final DateTime? revertedAt;

  const RedemptionRecord({
    required this.id,
    required this.couponId,
    required this.couponCode,
    required this.dealTitle,
    required this.userName,
    required this.redeemedAt,
    required this.isReverted,
    this.revertedAt,
  });

  factory RedemptionRecord.fromJson(Map<String, dynamic> json) {
    return RedemptionRecord(
      id: json['id'] as String,
      couponId: json['coupon_id'] as String,
      couponCode: json['coupon_code'] as String,
      dealTitle: json['deal_title'] as String,
      userName: json['user_name'] as String,
      redeemedAt: DateTime.parse(json['redeemed_at'] as String),
      isReverted: json['is_reverted'] as bool? ?? false,
      revertedAt: json['reverted_at'] != null
          ? DateTime.parse(json['reverted_at'] as String)
          : null,
    );
  }

  /// 核销后是否仍在10分钟内（可撤销）
  bool get canRevert {
    if (isReverted) return false;
    return DateTime.now().difference(redeemedAt).inMinutes < 10;
  }
}

/// 扫码/核销过程中的错误类型枚举
enum ScanError {
  /// 券已核销
  alreadyUsed,
  /// 券已退款
  alreadyRefunded,
  /// 券已过期
  expired,
  /// 券不属于当前商家
  wrongMerchant,
  /// 券码不存在
  notFound,
  /// 券码格式无效
  invalidCode,
  /// 网络错误
  network,
  /// 服务器错误
  serverError,
  /// 超过10分钟无法撤销
  revertExpired,
  /// 未知错误
  unknown;

  /// 从 Edge Function 返回的 error 字段映射
  factory ScanError.fromString(String value) {
    switch (value) {
      case 'already_used':
        return ScanError.alreadyUsed;
      case 'already_refunded':
        return ScanError.alreadyRefunded;
      case 'expired':
        return ScanError.expired;
      case 'wrong_merchant':
        return ScanError.wrongMerchant;
      case 'not_found':
        return ScanError.notFound;
      case 'invalid_code':
        return ScanError.invalidCode;
      case 'revert_expired':
        return ScanError.revertExpired;
      case 'server_error':
        return ScanError.serverError;
      default:
        return ScanError.unknown;
    }
  }

  /// 用户友好的错误提示标题
  String get title {
    switch (this) {
      case ScanError.alreadyUsed:
        return 'Already Redeemed';
      case ScanError.alreadyRefunded:
        return 'Voucher Refunded';
      case ScanError.expired:
        return 'Voucher Expired';
      case ScanError.wrongMerchant:
        return 'Wrong Store';
      case ScanError.notFound:
        return 'Invalid Code';
      case ScanError.invalidCode:
        return 'Invalid Format';
      case ScanError.network:
        return 'Network Error';
      case ScanError.serverError:
        return 'Server Error';
      case ScanError.revertExpired:
        return 'Cannot Undo';
      case ScanError.unknown:
        return 'Error';
    }
  }
}

/// 扫码异常，携带错误类型和服务端返回的消息
class ScanException implements Exception {
  final ScanError error;
  final String message;
  final String? detail;

  const ScanException({
    required this.error,
    required this.message,
    this.detail,
  });

  @override
  String toString() => 'ScanException(${error.name}): $message';
}

/// 核销历史筛选条件
class RedemptionHistoryFilter {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? dealId;
  final String? dealTitle; // 用于显示 Deal 下拉选项名称

  const RedemptionHistoryFilter({
    this.dateFrom,
    this.dateTo,
    this.dealId,
    this.dealTitle,
  });

  RedemptionHistoryFilter copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? dealId,
    String? dealTitle,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearDeal = false,
  }) {
    return RedemptionHistoryFilter(
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      dealId: clearDeal ? null : (dealId ?? this.dealId),
      dealTitle: clearDeal ? null : (dealTitle ?? this.dealTitle),
    );
  }

  bool get hasFilter => dateFrom != null || dateTo != null || dealId != null;
}
