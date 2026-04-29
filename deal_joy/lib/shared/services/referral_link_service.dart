import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 处理 Referral Deep Link 和待绑定邀请码的本地存储
/// 注册成功后 app.dart 调用 consumePendingCode() 获取待应用的 code
class ReferralLinkService {
  static const _prefKey = 'pending_referral_code';
  static ReferralLinkService? _instance;
  ReferralLinkService._();
  static ReferralLinkService get instance => _instance ??= ReferralLinkService._();

  final _appLinks = AppLinks();

  /// 在 main() 中初始化，监听 cold start 和 foreground 的 deep link
  Future<void> init() async {
    // 处理 cold start（app 从未运行时通过链接启动）
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleUri(initialUri);
    }

    // 处理 foreground（app 已在后台时收到新链接）
    _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  void _handleUri(Uri uri) {
    // 仅处理 /invite 路径
    if (uri.path == '/invite' || uri.path == '/invite/') {
      final ref = uri.queryParameters['ref'];
      if (ref != null && ref.isNotEmpty) {
        storePendingCode(ref.trim().toUpperCase());
      }
    }
  }

  /// 存储待应用的 referral code（deep link 解析后调用）
  Future<void> storePendingCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, code);
  }

  /// 读取并删除待应用的 referral code（注册成功后调用，防止重复应用）
  Future<String?> consumePendingCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code != null) {
      await prefs.remove(_prefKey);
    }
    return code;
  }

  /// 生成可分享的 invite URL
  String buildShareUrl(String referralCode) =>
      'https://crunchyplum.com/invite?ref=$referralCode';
}
