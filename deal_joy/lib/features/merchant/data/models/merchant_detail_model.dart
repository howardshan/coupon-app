import 'merchant_hour_model.dart';
import 'merchant_photo_model.dart';

/// 商家详情页聚合模型（含照片+营业时间）
class MerchantDetailModel {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final double? lat;
  final double? lng;
  final List<String> tags;
  final double? pricePerPerson;
  final String? parkingInfo;
  final bool wifi;
  final String? reservationUrl;
  final int? establishedYear;
  final List<MerchantPhotoModel> photos;
  final List<MerchantHourModel> hours;
  final String headerPhotoStyle; // 'single' 或 'triple'
  final List<String> headerPhotos; // triple 模式 3 张 URL

  const MerchantDetailModel({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.address,
    this.phone,
    this.lat,
    this.lng,
    this.tags = const [],
    this.pricePerPerson,
    this.parkingInfo,
    this.wifi = false,
    this.reservationUrl,
    this.establishedYear,
    this.photos = const [],
    this.hours = const [],
    this.headerPhotoStyle = 'single',
    this.headerPhotos = const [],
  });

  factory MerchantDetailModel.fromJson(Map<String, dynamic> json) {
    // 解析嵌套的 merchant_photos
    final photosRaw = json['merchant_photos'] as List? ?? [];
    final photos = photosRaw
        .map((p) => MerchantPhotoModel.fromJson(p as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // 解析嵌套的 merchant_hours
    final hoursRaw = json['merchant_hours'] as List? ?? [];
    final hours = hoursRaw
        .map((h) => MerchantHourModel.fromJson(h as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

    // 解析 tags（PostgreSQL text[] → Dart List）
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((t) => t.toString()).toList()
        : <String>[];

    return MerchantDetailModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      tags: tags,
      pricePerPerson: (json['price_per_person'] as num?)?.toDouble(),
      parkingInfo: json['parking_info'] as String?,
      wifi: json['wifi'] as bool? ?? false,
      reservationUrl: json['reservation_url'] as String?,
      establishedYear: json['established_year'] as int?,
      photos: photos,
      hours: hours,
      headerPhotoStyle: json['header_photo_style'] as String? ?? 'single',
      headerPhotos: (json['header_photos'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// 是否使用三图并排头图模式
  bool get useTripleHeader =>
      headerPhotoStyle == 'triple' && headerPhotos.length >= 3;

  /// 轮播照片 URL 列表（优先展示 cover 类型，无 cover 时兜底所有照片/logo）
  List<String> get allPhotoUrls {
    final coverUrls = photos
        .where((p) => p.photoType == 'cover')
        .map((p) => p.photoUrl)
        .toList();
    if (coverUrls.isNotEmpty) return coverUrls;
    // 兜底：无 cover 时展示所有照片
    final urls = photos.map((p) => p.photoUrl).toList();
    if (urls.isEmpty && logoUrl != null) urls.add(logoUrl!);
    return urls;
  }

  /// 环境照片（按 category 分组）
  Map<String, List<MerchantPhotoModel>> get environmentPhotos {
    final env = photos.where((p) => p.photoType == 'environment').toList();
    final grouped = <String, List<MerchantPhotoModel>>{};
    for (final photo in env) {
      final key = photo.category ?? 'other';
      grouped.putIfAbsent(key, () => []).add(photo);
    }
    return grouped;
  }

  /// 当前是否营业中
  bool get isOpenNow {
    if (hours.isEmpty) return false;
    final now = DateTime.now();
    // Dart: weekday 1=Mon...7=Sun → 转为数据库格式 0=Sun...6=Sat
    final dbDow = now.weekday == 7 ? 0 : now.weekday;
    final today = hours.where((h) => h.dayOfWeek == dbDow).firstOrNull;
    if (today == null || today.isClosed) return false;
    if (today.openTime == null || today.closeTime == null) return false;

    final currentMinutes = now.hour * 60 + now.minute;
    final openMinutes = _parseTimeToMinutes(today.openTime!);
    final closeMinutes = _parseTimeToMinutes(today.closeTime!);
    return currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
  }

  /// 今日营业时间文字
  String get todayHoursText {
    if (hours.isEmpty) return 'Hours not available';
    final now = DateTime.now();
    final dbDow = now.weekday == 7 ? 0 : now.weekday;
    final today = hours.where((h) => h.dayOfWeek == dbDow).firstOrNull;
    if (today == null) return 'Hours not available';
    return today.displayText;
  }

  /// 建店年数
  int? get yearsInBusiness {
    if (establishedYear == null) return null;
    return DateTime.now().year - establishedYear!;
  }

  static int _parseTimeToMinutes(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
}
