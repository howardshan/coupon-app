/// 语义化版本比较（仅比较数字段，忽略 build metadata）。
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
  final core = s.split('+').first.split('-').first;
  return core
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
}
