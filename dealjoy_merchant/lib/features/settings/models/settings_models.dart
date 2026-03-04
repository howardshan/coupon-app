// 设置模块数据模型
// 包含: NotificationPreferences / StaffMember / StaffRole

// ============================================================
// StaffRole 枚举 — 员工权限等级（V2 RBAC）
// ============================================================
enum StaffRole {
  /// 仅允许扫码核销
  scanOnly,

  /// 完整管理权限（等同于主账号）
  fullAccess;

  /// 转换为数据库存储的字符串值
  String get apiValue {
    switch (this) {
      case StaffRole.scanOnly:
        return 'scan_only';
      case StaffRole.fullAccess:
        return 'full_access';
    }
  }

  /// 从数据库字符串解析
  static StaffRole fromApiValue(String value) {
    switch (value) {
      case 'full_access':
        return StaffRole.fullAccess;
      case 'scan_only':
      default:
        return StaffRole.scanOnly;
    }
  }

  /// UI 显示标签
  String get displayName {
    switch (this) {
      case StaffRole.scanOnly:
        return 'Scan Only';
      case StaffRole.fullAccess:
        return 'Full Access';
    }
  }

  /// 权限描述文案
  String get description {
    switch (this) {
      case StaffRole.scanOnly:
        return 'Can only scan and redeem vouchers';
      case StaffRole.fullAccess:
        return 'Full management access (same as owner)';
    }
  }
}

// ============================================================
// NotificationPreferences — 通知偏好（本地存储）
// ============================================================
class NotificationPreferences {
  const NotificationPreferences({
    this.newOrder = true,
    this.redemption = true,
    this.dealApproved = true,
    this.reviewResult = true,
    this.systemAnnouncement = false,
  });

  /// 新订单通知
  final bool newOrder;

  /// 核销通知
  final bool redemption;

  /// Deal 审核结果通知
  final bool dealApproved;

  /// 评价通知
  final bool reviewResult;

  /// 系统公告（默认关闭）
  final bool systemAnnouncement;

  /// 不可变更新（copyWith 模式）
  NotificationPreferences copyWith({
    bool? newOrder,
    bool? redemption,
    bool? dealApproved,
    bool? reviewResult,
    bool? systemAnnouncement,
  }) {
    return NotificationPreferences(
      newOrder: newOrder ?? this.newOrder,
      redemption: redemption ?? this.redemption,
      dealApproved: dealApproved ?? this.dealApproved,
      reviewResult: reviewResult ?? this.reviewResult,
      systemAnnouncement: systemAnnouncement ?? this.systemAnnouncement,
    );
  }

  /// 转为 Map 方便批量写入 SharedPreferences
  Map<String, bool> toMap() {
    return {
      'newOrder': newOrder,
      'redemption': redemption,
      'dealApproved': dealApproved,
      'reviewResult': reviewResult,
      'systemAnnouncement': systemAnnouncement,
    };
  }

  /// 从 SharedPreferences 读取的 Map 构建实例
  factory NotificationPreferences.fromMap(Map<String, bool> map) {
    return NotificationPreferences(
      newOrder: map['newOrder'] ?? true,
      redemption: map['redemption'] ?? true,
      dealApproved: map['dealApproved'] ?? true,
      reviewResult: map['reviewResult'] ?? true,
      systemAnnouncement: map['systemAnnouncement'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationPreferences &&
        other.newOrder == newOrder &&
        other.redemption == redemption &&
        other.dealApproved == dealApproved &&
        other.reviewResult == reviewResult &&
        other.systemAnnouncement == systemAnnouncement;
  }

  @override
  int get hashCode => Object.hash(
        newOrder,
        redemption,
        dealApproved,
        reviewResult,
        systemAnnouncement,
      );

  @override
  String toString() {
    return 'NotificationPreferences('
        'newOrder: $newOrder, '
        'redemption: $redemption, '
        'dealApproved: $dealApproved, '
        'reviewResult: $reviewResult, '
        'systemAnnouncement: $systemAnnouncement)';
  }
}

// ============================================================
// StaffMember — 员工子账号数据（V2）
// ============================================================
class StaffMember {
  const StaffMember({
    required this.id,
    required this.userId,
    required this.email,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  /// 记录 ID（merchant_staff.id）
  final String id;

  /// 员工 Supabase Auth user_id
  final String userId;

  /// 员工邮箱（显示用）
  final String email;

  /// 员工姓名（显示用）
  final String name;

  /// 权限角色
  final StaffRole role;

  /// 创建时间
  final DateTime createdAt;

  /// 从 Supabase 查询结果构建（V2 使用）
  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as String,
      userId: json['staff_user_id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? 'Staff Member',
      role: StaffRole.fromApiValue(json['role'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// 不可变更新
  StaffMember copyWith({
    String? id,
    String? userId,
    String? email,
    String? name,
    StaffRole? role,
    DateTime? createdAt,
  }) {
    return StaffMember(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'StaffMember(id: $id, email: $email, role: $role)';
}
