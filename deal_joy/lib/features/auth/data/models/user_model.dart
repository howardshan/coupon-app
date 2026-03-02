class UserModel {
  final String id;
  final String email;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final String role; // 'user' | 'merchant' | 'admin'
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.role = 'user',
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String?,
        fullName: json['full_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        phone: json['phone'] as String?,
        role: json['role'] as String? ?? 'user',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'phone': phone,
        'role': role,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  UserModel copyWith({
    String? username,
    String? fullName,
    String? avatarUrl,
    String? phone,
  }) =>
      UserModel(
        id: id,
        email: email,
        username: username ?? this.username,
        fullName: fullName ?? this.fullName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        phone: phone ?? this.phone,
        role: role,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
