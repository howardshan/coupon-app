// 地区数据 Providers（从数据库加载 service_areas，替代硬编码 _locationData）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/service_area_model.dart';
import '../../data/repositories/service_area_repository.dart';

// Repository
final serviceAreaRepositoryProvider = Provider<ServiceAreaRepository>((ref) {
  return ServiceAreaRepository(ref.watch(supabaseClientProvider));
});

// 原始数据 — 不用 keepAlive，允许通过 ref.invalidate() 强制刷新
// 用户打开城市选择菜单时会触发 invalidate，确保看到最新数据
final serviceAreasProvider = FutureProvider<List<ServiceAreaModel>>((ref) async {
  final repo = ref.watch(serviceAreaRepositoryProvider);
  return repo.fetchServiceAreas();
});

// 派生：转为 Map<String, Map<String, List<String>>> 结构
// 直接替代 home_screen.dart 中的 _locationData 常量
final locationDataProvider =
    Provider<Map<String, Map<String, List<String>>>>((ref) {
  final areas = ref.watch(serviceAreasProvider).valueOrNull ?? [];
  final result = <String, Map<String, List<String>>>{};

  for (final area in areas) {
    if (area.level == 'city' &&
        area.metroName != null &&
        area.cityName != null) {
      result
          .putIfAbsent(area.stateName, () => <String, List<String>>{})
          .putIfAbsent(area.metroName!, () => <String>[])
          .add(area.cityName!);
    }
  }

  return result;
});
