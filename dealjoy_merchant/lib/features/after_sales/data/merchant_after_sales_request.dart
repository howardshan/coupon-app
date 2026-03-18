class MerchantAfterSalesRequest {
  const MerchantAfterSalesRequest({
    required this.id,
    required this.status,
    required this.reasonCode,
    required this.reasonDetail,
    required this.refundAmount,
    required this.userDisplayName,
    required this.timeline,
    this.userAttachments = const [],
    this.merchantAttachments = const [],
    this.platformAttachments = const [],
    this.merchantFeedback,
    this.platformFeedback,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String status;
  final String reasonCode;
  final String reasonDetail;
  final double refundAmount;
  final String userDisplayName;
  final List<AfterSalesTimelineEntry> timeline;
  final List<String> userAttachments;
  final List<String> merchantAttachments;
  final List<String> platformAttachments;
  final String? merchantFeedback;
  final String? platformFeedback;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get awaitingAction => status == 'pending';
  bool get awaitingPlatform => status == 'awaiting_platform';
  bool get resolved => status == 'refunded' || status == 'platform_rejected' || status == 'closed';

  Duration? get remainingTime {
    if (expiresAt == null) return null;
    return expiresAt!.difference(DateTime.now());
  }

  factory MerchantAfterSalesRequest.fromJson(Map<String, dynamic> json) {
    final timelineList = (json['timeline'] as List<dynamic>? ?? const [])
        .map((item) => AfterSalesTimelineEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    return MerchantAfterSalesRequest(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      reasonCode: json['reason_code'] as String? ?? 'other',
      reasonDetail: json['reason_detail'] as String? ?? '',
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      userDisplayName: json['user_display_name'] as String? ?? 'User',
      timeline: timelineList,
      userAttachments:
          (json['user_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      merchantAttachments:
          (json['merchant_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      platformAttachments:
          (json['platform_attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      merchantFeedback: json['merchant_feedback'] as String?,
      platformFeedback: json['platform_feedback'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
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
    return AfterSalesTimelineEntry(
      status: json['status'] as String? ?? 'update',
      actor: json['actor'] as String? ?? 'system',
      timestamp: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      note: json['note'] as String?,
      attachments:
          (json['attachments'] as List<dynamic>? ?? const []).whereType<String>().toList(),
    );
  }
}
