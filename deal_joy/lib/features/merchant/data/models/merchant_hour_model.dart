/// 营业时间模型（每行代表一天）
class MerchantHourModel {
  final String id;
  final int dayOfWeek; // 0=Sunday, 1=Monday, ..., 6=Saturday
  final String? openTime; // 'HH:MM:SS' 格式
  final String? closeTime;
  final bool isClosed;

  const MerchantHourModel({
    required this.id,
    required this.dayOfWeek,
    this.openTime,
    this.closeTime,
    this.isClosed = false,
  });

  factory MerchantHourModel.fromJson(Map<String, dynamic> json) =>
      MerchantHourModel(
        id: json['id'] as String,
        dayOfWeek: json['day_of_week'] as int,
        openTime: json['open_time'] as String?,
        closeTime: json['close_time'] as String?,
        isClosed: json['is_closed'] as bool? ?? false,
      );

  /// 星期名称缩写
  String get dayName => switch (dayOfWeek) {
        0 => 'Sun',
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        _ => '',
      };

  /// 格式化时间显示 '10:00 AM – 10:00 PM'
  String get displayText {
    if (isClosed || openTime == null || closeTime == null) return 'Closed';
    return '${_formatTime(openTime!)} – ${_formatTime(closeTime!)}';
  }

  /// 将 'HH:MM' 或 'HH:MM:SS' 转为 '10:00 AM' 格式
  static String _formatTime(String time) {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    var hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }
}
