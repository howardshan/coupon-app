import 'dart:math';

/// 计算两点间距离（英里），Haversine 公式
double haversineDistanceMiles(
    double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMiles = 3958.8;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) *
          cos(_toRad(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * asin(sqrt(a));
  return earthRadiusMiles * c;
}

double _toRad(double deg) => deg * pi / 180;
