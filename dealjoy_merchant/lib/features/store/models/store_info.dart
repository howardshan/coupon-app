// 门店信息相关数据模型
// 包含 StoreInfo、StorePhoto、StorePhotoType、BusinessHours

/// 照片类型枚举
/// storefront: 门头照（必传，限1张）
/// environment: 环境照（最多10张）
/// product: 菜品/商品照（最多10张）
enum StorePhotoType {
  storefront,
  environment,
  product;

  /// 转换为 API 字符串
  String get value => name;

  /// 从 API 字符串解析
  static StorePhotoType fromString(String value) {
    return StorePhotoType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => StorePhotoType.environment,
    );
  }

  /// 用户友好的显示标签
  String get displayLabel {
    switch (this) {
      case StorePhotoType.storefront:
        return 'Storefront';
      case StorePhotoType.environment:
        return 'Environment';
      case StorePhotoType.product:
        return 'Products';
    }
  }
}

/// 单张门店照片
class StorePhoto {
  const StorePhoto({
    required this.id,
    required this.url,
    required this.type,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String url;
  final StorePhotoType type;
  final int sortOrder;
  final DateTime createdAt;

  /// 从 Supabase 返回的 JSON 构造
  factory StorePhoto.fromJson(Map<String, dynamic> json) {
    return StorePhoto(
      id: json['id'] as String,
      url: json['photo_url'] as String,
      type: StorePhotoType.fromString(json['photo_type'] as String? ?? 'environment'),
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// 转为 JSON（用于调试）
  Map<String, dynamic> toJson() => {
        'id': id,
        'photo_url': url,
        'photo_type': type.value,
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
      };

  /// 复制并修改部分字段
  StorePhoto copyWith({
    String? id,
    String? url,
    StorePhotoType? type,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return StorePhoto(
      id: id ?? this.id,
      url: url ?? this.url,
      type: type ?? this.type,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 单天营业时间配置
/// day_of_week: 0=周日, 1=周一, ..., 6=周六
class BusinessHours {
  const BusinessHours({
    required this.dayOfWeek,
    required this.openTime,
    required this.closeTime,
    required this.isClosed,
  });

  final int dayOfWeek; // 0-6, 0=Sunday
  final String? openTime; // "HH:mm" 格式，is_closed 时为 null
  final String? closeTime; // "HH:mm" 格式，is_closed 时为 null
  final bool isClosed;

  /// 从 Supabase 返回的 JSON 构造
  factory BusinessHours.fromJson(Map<String, dynamic> json) {
    return BusinessHours(
      dayOfWeek: json['day_of_week'] as int,
      openTime: json['open_time'] as String?,
      closeTime: json['close_time'] as String?,
      isClosed: json['is_closed'] as bool? ?? false,
    );
  }

  /// 转为 API 请求 JSON
  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'open_time': openTime,
        'close_time': closeTime,
        'is_closed': isClosed,
      };

  /// 复制并修改部分字段
  BusinessHours copyWith({
    int? dayOfWeek,
    String? openTime,
    String? closeTime,
    bool? isClosed,
  }) {
    return BusinessHours(
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  /// 用于 UI 显示的时间字符串（如 "10:00 - 22:00" 或 "Closed"）
  String get displayText {
    if (isClosed) return 'Closed';
    if (openTime == null || closeTime == null) return 'Closed';
    return '$openTime - $closeTime';
  }

  /// 星期名称（英文）
  static String dayName(int dayOfWeek) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    return days[dayOfWeek % 7];
  }

  /// 星期名称简写（3字母）
  static String dayShortName(int dayOfWeek) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[dayOfWeek % 7];
  }
}

/// 完整门店信息
/// 聚合了基本信息、照片列表和营业时间
class StoreInfo {
  const StoreInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.phone,
    required this.address,
    required this.category,
    required this.tags,
    required this.isOnline,
    required this.status,
    required this.photos,
    required this.hours,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String? description;
  final String? phone;
  final String? address;
  final String? category;
  final List<String> tags;
  final bool isOnline;
  final String status; // pending | approved | rejected
  final List<StorePhoto> photos;
  final List<BusinessHours> hours;
  final double? latitude;
  final double? longitude;

  /// 从 Edge Function 返回的完整 JSON 构造
  factory StoreInfo.fromJson(Map<String, dynamic> json) {
    final storeJson = json['store'] as Map<String, dynamic>;
    final photosJson = json['photos'] as List<dynamic>? ?? [];
    final hoursJson = json['hours'] as List<dynamic>? ?? [];

    return StoreInfo(
      id: storeJson['id'] as String,
      name: storeJson['name'] as String? ?? '',
      description: storeJson['description'] as String?,
      phone: storeJson['phone'] as String?,
      address: storeJson['address'] as String?,
      category: storeJson['category'] as String?,
      tags: List<String>.from(storeJson['tags'] as List<dynamic>? ?? []),
      isOnline: storeJson['is_online'] as bool? ?? true,
      status: storeJson['status'] as String? ?? 'pending',
      photos: photosJson
          .map((e) => StorePhoto.fromJson(e as Map<String, dynamic>))
          .toList(),
      hours: hoursJson
          .map((e) => BusinessHours.fromJson(e as Map<String, dynamic>))
          .toList(),
      latitude: (storeJson['lat'] as num?)?.toDouble(),
      longitude: (storeJson['lng'] as num?)?.toDouble(),
    );
  }

  /// 门头照（storefront type，最多1张）
  StorePhoto? get storefrontPhoto {
    final storefront = photos.where((p) => p.type == StorePhotoType.storefront).toList();
    return storefront.isEmpty ? null : storefront.first;
  }

  /// 环境照列表
  List<StorePhoto> get environmentPhotos =>
      photos.where((p) => p.type == StorePhotoType.environment).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 菜品照列表
  List<StorePhoto> get productPhotos =>
      photos.where((p) => p.type == StorePhotoType.product).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 今日营业状态（根据当前本地时间判断）
  bool get isOpenNow {
    final now = DateTime.now();
    // Dart weekday: 1=Monday, 7=Sunday；转换为 0=Sunday, 1=Monday
    final todayDayOfWeek = now.weekday == 7 ? 0 : now.weekday;
    final todayHours = hours.where((h) => h.dayOfWeek == todayDayOfWeek).firstOrNull;
    if (todayHours == null || todayHours.isClosed) return false;
    if (todayHours.openTime == null || todayHours.closeTime == null) return false;

    // 解析营业时间
    final openParts = todayHours.openTime!.split(':');
    final closeParts = todayHours.closeTime!.split(':');
    final openMinutes =
        int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes =
        int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
    final currentMinutes = now.hour * 60 + now.minute;

    return currentMinutes >= openMinutes && currentMinutes < closeMinutes;
  }

  /// 复制并修改部分字段
  StoreInfo copyWith({
    String? id,
    String? name,
    String? description,
    String? phone,
    String? address,
    String? category,
    List<String>? tags,
    bool? isOnline,
    String? status,
    List<StorePhoto>? photos,
    List<BusinessHours>? hours,
    double? latitude,
    double? longitude,
  }) {
    return StoreInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      isOnline: isOnline ?? this.isOnline,
      status: status ?? this.status,
      photos: photos ?? this.photos,
      hours: hours ?? this.hours,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
