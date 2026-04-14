// 地区数据 Repository（查询 service_areas 表）

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/service_area_model.dart';

class ServiceAreaRepository {
  final SupabaseClient _client;

  ServiceAreaRepository(this._client);

  /// 获取所有启用的地区数据，按 state → metro → sort_order 排序
  Future<List<ServiceAreaModel>> fetchServiceAreas() async {
    final res = await _client
        .from('service_areas')
        .select()
        .eq('is_active', true)
        .order('state_name', ascending: true)
        .order('metro_name', ascending: true)
        .order('sort_order', ascending: true);

    return (res as List).map((e) => ServiceAreaModel.fromJson(e)).toList();
  }
}
