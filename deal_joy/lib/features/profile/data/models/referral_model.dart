class ReferralConfig {
  final bool enabled;
  final double bonusAmount;

  const ReferralConfig({required this.enabled, required this.bonusAmount});

  factory ReferralConfig.fromJson(Map<String, dynamic> json) {
    return ReferralConfig(
      enabled: json['enabled'] as bool? ?? false,
      bonusAmount: (json['bonus_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static const ReferralConfig disabled = ReferralConfig(enabled: false, bonusAmount: 0.0);
}

class ReferralRecord {
  final String id;
  final String refereeId;
  final String? refereeFirstName;
  final String status; // 'pending' | 'credited' | 'cancelled'
  final double bonusAmount;
  final DateTime createdAt;
  final DateTime? creditedAt;

  const ReferralRecord({
    required this.id,
    required this.refereeId,
    this.refereeFirstName,
    required this.status,
    required this.bonusAmount,
    required this.createdAt,
    this.creditedAt,
  });

  factory ReferralRecord.fromJson(Map<String, dynamic> json) {
    final refereeData = json['users'] as Map<String, dynamic>?;
    final fullName = refereeData?['full_name'] as String? ?? '';
    final firstName = fullName.isNotEmpty ? fullName.split(' ').first : null;

    return ReferralRecord(
      id: json['id'] as String? ?? '',
      refereeId: json['referee_id'] as String? ?? '',
      refereeFirstName: firstName?.isNotEmpty == true ? firstName : null,
      status: json['status'] as String? ?? 'pending',
      bonusAmount: (json['bonus_amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      creditedAt: json['credited_at'] != null
          ? DateTime.tryParse(json['credited_at'] as String)
          : null,
    );
  }

  bool get isCredited => status == 'credited';
  bool get isPending => status == 'pending';
}
