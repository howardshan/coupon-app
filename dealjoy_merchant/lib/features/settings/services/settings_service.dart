// 设置模块服务层
// 负责: 通知偏好读写（SharedPreferences）/ 员工子账号 CRUD（V2 存根）/ 退出登录

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../store/services/store_service.dart';
import '../models/settings_models.dart';

// ============================================================
// SharedPreferences 键名常量
// 前缀统一用 dealjoy_notif_ 避免与其他模块冲突
// ============================================================
class _NotifKeys {
  static const String newOrder = 'dealjoy_notif_new_order';
  static const String redemption = 'dealjoy_notif_redemption';
  static const String dealApproved = 'dealjoy_notif_deal_approved';
  static const String reviewResult = 'dealjoy_notif_review_result';
  static const String systemAnnouncement = 'dealjoy_notif_system_announcement';
}

// ============================================================
// SettingsService — 设置模块所有业务逻辑
// ============================================================
class SettingsService {
  SettingsService(this._supabase);

  final SupabaseClient _supabase;

  // ----------------------------------------------------------
  // 1. 读取通知偏好（从 SharedPreferences）
  //    若从未设置过则返回默认值（新订单/核销/Deal审核/评价 默认开；系统公告默认关）
  // ----------------------------------------------------------
  Future<NotificationPreferences> loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    return NotificationPreferences(
      newOrder: prefs.getBool(_NotifKeys.newOrder) ?? true,
      redemption: prefs.getBool(_NotifKeys.redemption) ?? true,
      dealApproved: prefs.getBool(_NotifKeys.dealApproved) ?? true,
      reviewResult: prefs.getBool(_NotifKeys.reviewResult) ?? true,
      systemAnnouncement: prefs.getBool(_NotifKeys.systemAnnouncement) ?? false,
    );
  }

  // ----------------------------------------------------------
  // 2. 保存通知偏好（写入 SharedPreferences）
  //    onChange 回调中实时调用，确保切换即时持久化
  // ----------------------------------------------------------
  Future<void> saveNotificationPreferences(
    NotificationPreferences prefs,
  ) async {
    final sp = await SharedPreferences.getInstance();

    // 批量写入，使用 Future.wait 并发提升性能
    await Future.wait([
      sp.setBool(_NotifKeys.newOrder, prefs.newOrder),
      sp.setBool(_NotifKeys.redemption, prefs.redemption),
      sp.setBool(_NotifKeys.dealApproved, prefs.dealApproved),
      sp.setBool(_NotifKeys.reviewResult, prefs.reviewResult),
      sp.setBool(_NotifKeys.systemAnnouncement, prefs.systemAnnouncement),
    ]);
  }

  // ----------------------------------------------------------
  // 3. [V2 存根] 获取商家员工列表
  //    V2 实现时：查询 merchant_staff JOIN auth.users 获取邮箱和姓名
  // ----------------------------------------------------------
  Future<List<StaffMember>> fetchStaffMembers(String merchantId) async {
    // V2 存根：直接返回空列表，不查询数据库
    // V2 实现:
    // final data = await _supabase
    //     .from('merchant_staff')
    //     .select('*, profiles(email, display_name)')
    //     .eq('merchant_id', merchantId)
    //     .order('created_at');
    // return data.map(StaffMember.fromJson).toList();
    return [];
  }

  // ----------------------------------------------------------
  // 4. [V2 存根] 邀请员工
  //    V2 实现时：先通过邮箱查找用户，再插入 merchant_staff 记录
  // ----------------------------------------------------------
  Future<void> inviteStaff(
    String merchantId,
    String email,
    StaffRole role,
  ) async {
    // V2 存根：仅验证参数格式，不执行实际操作
    if (email.isEmpty) throw Exception('Email is required');
    // V2 实现:
    // final user = await _findUserByEmail(email);
    // await _supabase.from('merchant_staff').insert({
    //   'merchant_id': merchantId,
    //   'staff_user_id': user.id,
    //   'role': role.apiValue,
    //   'invited_by': _supabase.auth.currentUser?.id,
    // });
  }

  // ----------------------------------------------------------
  // 5. [V2 存根] 移除员工
  //    V2 实现时：删除 merchant_staff 记录
  // ----------------------------------------------------------
  Future<void> removeStaff(String staffId) async {
    // V2 存根：空操作
    // V2 实现:
    // await _supabase
    //     .from('merchant_staff')
    //     .delete()
    //     .eq('id', staffId);
  }

  // ----------------------------------------------------------
  // 6. 退出登录
  //    调用 Supabase Auth signOut，清除本地 Session
  // ----------------------------------------------------------
  Future<void> signOut() async {
    // 清除品牌管理员持久化的门店 ID
    await StoreService.clearPersistedMerchantId();
    await _supabase.auth.signOut();
  }

  // ----------------------------------------------------------
  // 辅助: 获取当前登录用户（快捷方法）
  // ----------------------------------------------------------
  User? get currentUser => _supabase.auth.currentUser;

  /// 当前用户邮箱
  String get currentUserEmail => currentUser?.email ?? '';
}
