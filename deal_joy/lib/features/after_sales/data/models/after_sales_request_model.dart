import 'package:collection/collection.dart';

enum AfterSalesReason {
  mistakenRedemption('mistaken_redemption', 'Wrong redemption'),
  badExperience('bad_experience', 'Bad experience'),
  serviceIssue('service_issue', 'Service issue'),
  qualityIssue('quality_issue', 'Quality issue'),
  other('other', 'Other');

  const AfterSalesReason(this.code, this.label);
  final String code;
  final String label;

  static AfterSalesReason? fromCode(String? value) {
    if (value == null) return null;
    return AfterSalesReason.values.firstWhereOrNull((r) => r.code == value);
  }
}

class AfterSalesTimelineEntry {
  const AfterSalesTimelineEntry({
    required this.status,
    required this.actor,
    required this.timestamp,
    this.note,
    this.attachments = const [],
  });

  final String status;
  final String actor;
  final DateTime timestamp;
  final String? note;
  final List<String> attachments;

  factory AfterSalesTimelineEntry.fromJson(Map<String, dynamic> json) {
    final attachmentList = (json['attachments'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const [];
    return AfterSalesTimelineEntry(
      status: json['status'] as String? ?? 'unknown',
      actor: json['actor'] as String? ?? 'system',
      note: json['note'] as String?,
      timestamp: DateTime.parse(json['at'] as String? ?? DateTime.now().toIso8601String()),
      attachments: attachmentList,
    );
  }
}

class AfterSalesEventModel {
  const AfterSalesEventModel({
    required this.id,
    required this.action,
    required this.actorRole,
    required this.createdAt,
    this.note,
    this.attachments = const [],
  });

  final int id;
  final String action;
  final String actorRole;
  final DateTime createdAt;
  final String? note;
  final List<String> attachments;

  factory AfterSalesEventModel.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>?;
    final note = payload?['note'] as String? ?? payload?['reason'] as String?;
    final attachmentList = (payload?['attachments'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const [];
    return AfterSalesEventModel(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      action: json['action'] as String? ?? 'event',
      actorRole: json['actor_role'] as String? ?? 'system',
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      note: note,
      attachments: attachmentList,
    );
  }
}

class AfterSalesRequestModel {
  const AfterSalesRequestModel({
    required this.id,
    required this.orderId,
    required this.couponId,
    required this.status,
    required this.reasonCode,
    required this.reasonDetail,
    required this.refundAmount,
    required this.timeline,
    required this.createdAt,
    this.merchantFeedback,
    this.platformFeedback,
    this.userAttachments = const [],
    this.merchantAttachments = const [],
    this.platformAttachments = const [],
    this.events = const [],
  });

  final String id;
  final String orderId;
  final String couponId;
  final String status;
  final String reasonCode;
  final String reasonDetail;
  final double refundAmount;
  final List<AfterSalesTimelineEntry> timeline;
  final DateTime createdAt;
  final String? merchantFeedback;
  final String? platformFeedback;
  final List<String> userAttachments;
  final List<String> merchantAttachments;
  final List<String> platformAttachments;
  final List<AfterSalesEventModel> events;

  bool get awaitingMerchant => status == 'pending';
  bool get awaitingPlatform => status == 'awaiting_platform';
  bool get merchantRejected => status == 'merchant_rejected';
  bool get completed => status == 'refunded' || status == 'platform_rejected' || status == 'closed';

  AfterSalesReason? get reason => AfterSalesReason.fromCode(reasonCode);

  factory AfterSalesRequestModel.fromJson(Map<String, dynamic> json) {
    final timelineList = (json['timeline'] as List<dynamic>?)
            ?.map((item) => AfterSalesTimelineEntry.fromJson(item as Map<String, dynamic>))
            .toList() ??
        const [];
    final eventsList = (json['after_sales_events'] as List<dynamic>?)
            ?.map((item) => AfterSalesEventModel.fromJson(item as Map<String, dynamic>))
            .toList() ??
        const [];
    return AfterSalesRequestModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      couponId: json['coupon_id'] as String,
      status: json['status'] as String? ?? 'pending',
      reasonCode: json['reason_code'] as String? ?? 'other',
      reasonDetail: json['reason_detail'] as String? ?? '',
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      timeline: timelineList,
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      merchantFeedback: json['merchant_feedback'] as String?,
      platformFeedback: json['platform_feedback'] as String?,
      userAttachments:
          (json['user_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      merchantAttachments:
          (json['merchant_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      platformAttachments:
          (json['platform_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      events: eventsList,
    );
  }
}

class AfterSalesUploadSlot {
  const AfterSalesUploadSlot({
    required this.path,
    required this.signedUrl,
    required this.token,
    required this.bucket,
  });

  final String path;
  final String signedUrl;
  final String token;
  final String bucket;

  factory AfterSalesUploadSlot.fromJson(Map<String, dynamic> json) {
    return AfterSalesUploadSlot(
      path: json['path'] as String,
      signedUrl: json['signedUrl'] as String,
      token: json['token'] as String,
      bucket: json['bucket'] as String? ?? 'after-sales-evidence',
    );
  }
}
