// 员工数据模型
// 对应 merchant_staff 表

/// 员工角色枚举
enum StaffRole {
  /// 店长 — 管理该店全部功能（不含门店设置/删除）
  manager,

  /// 核销员/收银 — 只能扫码 + 看订单列表
  cashier,

  /// 客服 — 核销 + 订单 + 回复评价
  service;

  /// 转换为 API 字符串
  String get value => name;

  /// 从 API 字符串解析
  static StaffRole fromString(String? value) {
    return StaffRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => StaffRole.cashier,
    );
  }

  /// 用户友好的显示标签
  String get displayLabel {
    switch (this) {
      case StaffRole.manager:
        return 'Manager';
      case StaffRole.cashier:
        return 'Cashier';
      case StaffRole.service:
        return 'Service';
    }
  }

  /// 角色描述
  String get description {
    switch (this) {
      case StaffRole.manager:
        return 'Full store management except settings';
      case StaffRole.cashier:
        return 'Scan vouchers and view orders';
      case StaffRole.service:
        return 'Scan, orders, and reply to reviews';
    }
  }
}

/// 员工信息
class StaffMember {
  const StaffMember({
    required this.id,
    required this.userId,
    required this.merchantId,
    required this.role,
    this.nickname,
    required this.isActive,
    this.email,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 记录 ID
  final String id;

  /// 关联的 auth.users ID
  final String userId;

  /// 关联的门店 ID
  final String merchantId;

  /// 角色
  final StaffRole role;

  /// 昵称（由管理员设置的备注名）
  final String? nickname;

  /// 是否启用
  final bool isActive;

  /// 员工邮箱（从 auth.users join 获取）
  final String? email;

  /// 邀请者 user_id
  final String? invitedBy;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  /// 从 Edge Function 返回的 JSON 构造
  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      role: StaffRole.fromString(json['role'] as String?),
      nickname: json['nickname'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      email: json['email'] as String?,
      invitedBy: json['invited_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// 显示名称（优先昵称，否则邮箱前缀）
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    if (email != null && email!.isNotEmpty) {
      return email!.split('@').first;
    }
    return 'Staff';
  }

  /// 复制并修改部分字段
  StaffMember copyWith({
    String? id,
    String? userId,
    String? merchantId,
    StaffRole? role,
    String? nickname,
    bool? isActive,
    String? email,
    String? invitedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StaffMember(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      merchantId: merchantId ?? this.merchantId,
      role: role ?? this.role,
      nickname: nickname ?? this.nickname,
      isActive: isActive ?? this.isActive,
      email: email ?? this.email,
      invitedBy: invitedBy ?? this.invitedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 待处理的员工邀请
class StaffInvitation {
  const StaffInvitation({
    required this.id,
    required this.merchantId,
    required this.invitedEmail,
    required this.role,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String merchantId;
  final String invitedEmail;
  final StaffRole role;
  final String status; // pending / accepted / expired / cancelled
  final DateTime expiresAt;
  final DateTime createdAt;

  /// 是否已过期
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// 从 JSON 构造
  factory StaffInvitation.fromJson(Map<String, dynamic> json) {
    return StaffInvitation(
      id: json['id'] as String? ?? '',
      merchantId: json['merchant_id'] as String? ?? '',
      invitedEmail: json['invited_email'] as String? ?? '',
      role: StaffRole.fromString(json['role'] as String?),
      status: json['status'] as String? ?? 'pending',
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
