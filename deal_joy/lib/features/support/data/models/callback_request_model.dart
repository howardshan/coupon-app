class CallbackRequestModel {
  final String id;
  final String userId;
  final String phone;
  final String preferredTimeSlot;
  final String? description;
  final String status;
  final DateTime createdAt;

  const CallbackRequestModel({
    required this.id,
    required this.userId,
    required this.phone,
    required this.preferredTimeSlot,
    this.description,
    required this.status,
    required this.createdAt,
  });

  factory CallbackRequestModel.fromJson(Map<String, dynamic> json) {
    return CallbackRequestModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      preferredTimeSlot: json['preferred_time_slot'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 用于插入数据库的 JSON（不含 id、status、created_at，由数据库生成）
  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'phone': phone,
      'preferred_time_slot': preferredTimeSlot,
      if (description != null && description!.isNotEmpty)
        'description': description,
    };
  }
}
