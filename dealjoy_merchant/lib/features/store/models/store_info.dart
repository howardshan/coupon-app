// 门店信息相关数据模型
// 包含 StoreInfo、StorePhoto、StorePhotoType、BusinessHours

/// 照片类型枚举
/// storefront: 门头照（必传，限1张）
/// environment: 环境照（最多10张）
/// product: 菜品/商品照（最多10张）
enum StorePhotoType {
  cover,
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
      case StorePhotoType.cover:
        return 'Cover';
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

/// 商家证件文档（来自 merchant_documents 表）
class MerchantDoc {
  const MerchantDoc({
    required this.documentType,
    required this.fileUrl,
  });

  final String documentType;
  final String fileUrl;

  factory MerchantDoc.fromJson(Map<String, dynamic> json) {
    return MerchantDoc(
      documentType: json['document_type'] as String,
      fileUrl: json['file_url'] as String,
    );
  }

  /// 用户友好的显示标签
  String get displayLabel {
    switch (documentType) {
      case 'business_license':
        return 'Business License';
      case 'health_permit':
        return 'Health Permit';
      case 'food_service_license':
        return 'Food Service License';
      case 'cosmetology_license':
        return 'Cosmetology License';
      case 'massage_therapy_license':
        return 'Massage Therapy License';
      case 'facility_license':
        return 'Facility License';
      case 'general_business_permit':
        return 'General Business Permit';
      case 'storefront_photo':
        return 'Storefront Photo';
      case 'owner_id':
        return 'Owner ID';
      default:
        return documentType;
    }
  }
}

/// 完整门店信息
/// 聚合了基本信息、照片列表、营业时间和专业资料
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
    // 专业资料（来自 merchants 表注册信息）
    this.companyName,
    this.contactName,
    this.contactEmail,
    this.ein,
    this.city,
    this.website,
    // 首页封面图（存在 merchants 表，用于客户端首页 deal 卡片 fallback）
    this.homepageCoverUrl,
    // 头图模式: 'single'(轮播) 或 'triple'(三图并排)
    this.headerPhotoStyle = 'single',
    // triple 模式下选中的 3 张头图 URL
    this.headerPhotos = const [],
    // 注册时上传的门头照（来自 merchant_documents 表）
    this.registrationStorefrontUrl,
    // 注册时上传的所有证件（来自 merchant_documents 表）
    this.documents = const [],
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

  // 专业资料字段
  final String? companyName;
  final String? contactName;
  final String? contactEmail;
  final String? ein;
  final String? city;
  final String? website;

  // 首页封面图 URL（从 merchants 表获取）
  final String? homepageCoverUrl;

  // 头图模式: 'single'(轮播) 或 'triple'(三图并排)
  final String headerPhotoStyle;

  // triple 模式下选中的 3 张头图 URL
  final List<String> headerPhotos;

  // 注册时上传的门头照 URL（从 merchant_documents 表获取）
  final String? registrationStorefrontUrl;

  // 注册时上传的所有证件
  final List<MerchantDoc> documents;

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
      homepageCoverUrl: storeJson['homepage_cover_url'] as String?,
      headerPhotoStyle: storeJson['header_photo_style'] as String? ?? 'single',
      headerPhotos: List<String>.from(storeJson['header_photos'] as List<dynamic>? ?? []),
      // 专业资料从 storeJson 中读取（merchants 表字段）
      companyName: storeJson['company_name'] as String?,
      contactName: storeJson['contact_name'] as String?,
      contactEmail: storeJson['contact_email'] as String?,
      ein: storeJson['ein'] as String?,
      city: storeJson['city'] as String?,
      website: storeJson['website'] as String?,
    );
  }

  /// 封面照列表（cover type，最多5张，按 sortOrder 排序）
  List<StorePhoto> get coverPhotos =>
      photos.where((p) => p.type == StorePhotoType.cover).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 门头照列表（storefront type，最多3张，按 sortOrder 排序）
  List<StorePhoto> get storefrontPhotos =>
      photos.where((p) => p.type == StorePhotoType.storefront).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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

  /// 获取最佳门头照 URL（优先 merchant_photos，其次 merchant_documents 的注册照）
  String? get bestStorefrontUrl {
    final fromPhotos = storefrontPhotos.firstOrNull?.url;
    if (fromPhotos != null) return fromPhotos;
    return registrationStorefrontUrl;
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
    String? homepageCoverUrl,
    String? headerPhotoStyle,
    List<String>? headerPhotos,
    String? companyName,
    String? contactName,
    String? contactEmail,
    String? ein,
    String? city,
    String? website,
    String? registrationStorefrontUrl,
    List<MerchantDoc>? documents,
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
      homepageCoverUrl: homepageCoverUrl ?? this.homepageCoverUrl,
      headerPhotoStyle: headerPhotoStyle ?? this.headerPhotoStyle,
      headerPhotos: headerPhotos ?? this.headerPhotos,
      companyName: companyName ?? this.companyName,
      contactName: contactName ?? this.contactName,
      contactEmail: contactEmail ?? this.contactEmail,
      ein: ein ?? this.ein,
      city: city ?? this.city,
      website: website ?? this.website,
      registrationStorefrontUrl: registrationStorefrontUrl ?? this.registrationStorefrontUrl,
      documents: documents ?? this.documents,
    );
  }
}
