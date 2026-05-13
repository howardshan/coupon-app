/// 语义化版本比较（仅比较数字段，忽略 build metadata）。
/// 返回负数表示 [a] 小于 [b]，0 相等，正数表示 [a] 大于 [b]。
int compareSemver(String a, String b) {
  final pa = _numericParts(a);
  final pb = _numericParts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _numericParts(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return [0];
  // 去掉 +build / -prerelease 等常见后缀，只保留主.次.修订数字段
  final core = s.split('+').first.split('-').first;
  return core
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
}
