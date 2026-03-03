import 'package:shared_preferences/shared_preferences.dart';

/// 本地浏览历史，使用 shared_preferences 持久化
class HistoryRepository {
  static const _dealKey = 'viewed_deal_ids';
  static const _merchantKey = 'viewed_merchant_ids';
  static const _maxItems = 50;

  // ── Deal 历史 ──────────────────────────────────────────────

  /// 将 dealId 插入历史最前面（自动去重，超出50条时截断）
  Future<void> addToHistory(String dealId) async {
    await _addToList(_dealKey, dealId);
  }

  /// 读取 deal 历史 ID 列表（最新在前）
  Future<List<String>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_dealKey) ?? [];
  }

  /// 清空 deal 浏览历史
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dealKey);
  }

  // ── Store 历史 ─────────────────────────────────────────────

  /// 将 merchantId 插入历史最前面
  Future<void> addMerchantToHistory(String merchantId) async {
    await _addToList(_merchantKey, merchantId);
  }

  /// 读取 merchant 历史 ID 列表（最新在前）
  Future<List<String>> getMerchantHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_merchantKey) ?? [];
  }

  /// 清空 store 浏览历史
  Future<void> clearMerchantHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_merchantKey);
  }

  // ── 内部辅助 ───────────────────────────────────────────────

  Future<void> _addToList(String key, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(key) ?? [];
    ids.remove(id); // 去重
    ids.insert(0, id); // 最新的放最前
    if (ids.length > _maxItems) ids.removeRange(_maxItems, ids.length);
    await prefs.setStringList(key, ids);
  }
}
