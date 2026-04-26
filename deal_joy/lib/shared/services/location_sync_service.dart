import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 用户登录后同步 GPS 位置到 users 表，用于地理推送通知
class LocationSyncService {
  final _supabase = Supabase.instance.client;

  /// 获取 GPS 并同步到 users 表，失败静默忽略
  Future<void> syncUserLocation(String userId) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 10));

      await _supabase.from('users').upsert({
        'id': userId,
        'last_lat': pos.latitude,
        'last_lng': pos.longitude,
        'last_location_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // 位置同步失败不影响主流程
    }
  }
}
