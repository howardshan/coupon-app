// 法律文档 Riverpod Providers
// 包含：数据模型、Repository、Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/device_context_helper.dart';
import 'supabase_provider.dart';

// ─────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────

/// 待确认的法律文档（用户尚未同意的新版本）
class PendingConsent {
  final String documentId;
  final String slug;
  final String title;
  final int currentVersion;
  final int userVersion;
  final String? summaryOfChanges;

  const PendingConsent({
    required this.documentId,
    required this.slug,
    required this.title,
    required this.currentVersion,
    required this.userVersion,
    this.summaryOfChanges,
  });

  factory PendingConsent.fromJson(Map<String, dynamic> json) {
    return PendingConsent(
      documentId: json['document_id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      currentVersion: (json['current_version'] as num?)?.toInt() ?? 0,
      userVersion: (json['user_version'] as num?)?.toInt() ?? 0,
      summaryOfChanges: json['summary_of_changes'] as String?,
    );
  }
}

/// 法律文档正文内容（按 slug 查询的完整文档）
class LegalDocumentContent {
  final String documentId;
  final String slug;
  final String title;
  final int version;
  final String contentHtml;
  final String? summaryOfChanges;
  final DateTime? publishedAt;

  const LegalDocumentContent({
    required this.documentId,
    required this.slug,
    required this.title,
    required this.version,
    required this.contentHtml,
    this.summaryOfChanges,
    this.publishedAt,
  });

  factory LegalDocumentContent.fromJson(Map<String, dynamic> json) {
    return LegalDocumentContent(
      documentId: json['document_id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 0,
      contentHtml: json['content_html'] as String? ?? '',
      summaryOfChanges: json['summary_of_changes'] as String?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String? ?? '')
          : null,
    );
  }
}

// ─────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────

/// 法律文档数据访问层
class LegalRepository {
  final SupabaseClient _supabase;

  LegalRepository(this._supabase);

  /// 检查当前用户待同意的法律文档列表
  /// 调用 RPC: check_pending_consents(p_user_id, p_role)
  /// 若用户未登录则返回空列表
  Future<List<PendingConsent>> checkPendingConsents() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    // 从 users 表查询用户角色
    String role = 'customer';
    try {
      final userData = await _supabase
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (userData != null && userData['role'] != null) {
        role = userData['role'] as String? ?? 'customer';
      }
    } catch (_) {
      // 查询失败时使用默认角色 customer
    }

    final result = await _supabase.rpc(
      'check_pending_consents',
      params: {
        'p_user_id': user.id,
        'p_role': role,
      },
    );

    if (result == null) return [];
    final list = result as List<dynamic>;
    return list
        .map((e) => PendingConsent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 按 slug（和可选版本号）获取法律文档正文
  /// 调用 RPC: get_legal_document_content(p_slug, p_version)
  Future<LegalDocumentContent?> getDocumentContent(
    String slug, {
    int? version,
  }) async {
    final params = <String, dynamic>{'p_slug': slug};
    if (version != null) {
      params['p_version'] = version;
    }

    final result = await _supabase.rpc(
      'get_legal_document_content',
      params: params,
    );

    if (result == null) return null;

    // RPC 可能返回单行 Map 或单元素 List
    LegalDocumentContent? doc;
    if (result is List) {
      if (result.isEmpty) return null;
      doc = LegalDocumentContent.fromJson(
          result.first as Map<String, dynamic>);
    } else if (result is Map<String, dynamic>) {
      doc = LegalDocumentContent.fromJson(result);
    }
    if (doc == null) return null;

    // 调用 render_legal_document RPC 替换占位符
    try {
      final rendered = await _supabase.rpc(
        'render_legal_document',
        params: {'p_content_html': doc.contentHtml},
      );
      if (rendered is String) {
        return LegalDocumentContent(
          documentId: doc.documentId,
          slug: doc.slug,
          title: doc.title,
          version: doc.version,
          contentHtml: rendered,
          summaryOfChanges: doc.summaryOfChanges,
          publishedAt: doc.publishedAt,
        );
      }
    } catch (_) {
      // 占位符替换失败不阻塞展示，返回原始内容
    }
    return doc;
  }

  /// 记录用户对指定法律文档的同意
  /// 调用 RPC: record_user_consent(...)
  /// 自动采集 device_info / app_version / user_agent / platform
  Future<void> recordConsent({
    required String documentSlug,
    required String consentMethod,
    required String triggerContext,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final ctx = await DeviceContextHelper.get();

    await _supabase.rpc(
      'record_user_consent',
      params: {
        'p_user_id': user.id,
        'p_document_slug': documentSlug,
        'p_actor_role': 'user',
        'p_consent_method': consentMethod,
        'p_trigger_context': triggerContext,
        'p_ip_address': null, // 服务端暂无可靠获取方式（pooler 屏蔽了真实 IP）
        'p_user_agent': ctx.userAgent,
        'p_device_info': ctx.deviceInfo,
        'p_app_version': ctx.appVersion,
        'p_platform': ctx.platform,
        'p_locale': 'en',
      },
    );
  }

  /// 记录法律事件（非同意）：consent_prompted / consent_declined / consent_superseded
  /// 调用 RPC: record_legal_event(...)
  /// 仅写入 legal_audit_log，不修改 user_consents 表
  Future<void> recordLegalEvent({
    required String eventType,
    required String documentSlug,
    Map<String, dynamic>? details,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final ctx = await DeviceContextHelper.get();

    await _supabase.rpc(
      'record_legal_event',
      params: {
        'p_user_id': user.id,
        'p_event_type': eventType,
        'p_document_slug': documentSlug,
        'p_actor_role': 'user',
        'p_details': details ?? <String, dynamic>{},
        'p_ip_address': null,
        'p_user_agent': ctx.userAgent,
        'p_device_info': ctx.deviceInfo,
        'p_app_version': ctx.appVersion,
        'p_platform': ctx.platform,
        'p_locale': 'en',
      },
    );
  }
}

// ─────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────

/// LegalRepository Provider
final legalRepositoryProvider = Provider<LegalRepository>((ref) {
  return LegalRepository(ref.watch(supabaseClientProvider));
});

/// 当前用户待同意的法律文档列表
/// 调用 RPC: check_pending_consents
/// autoDispose：登录 / 账号切换 / App 生命周期变化时自动重新检查
final pendingConsentsProvider =
    FutureProvider.autoDispose<List<PendingConsent>>((ref) {
  return ref.watch(legalRepositoryProvider).checkPendingConsents();
});

/// 按 slug 获取法律文档正文（FutureProvider.family，参数为 slug）
/// 调用 RPC: get_legal_document_content
/// autoDispose：关闭文档页面后缓存立即失效，下次打开一定拉取最新版本
/// （保证 admin 发布新版本后用户能立即看到更新）
final legalDocumentContentProvider =
    FutureProvider.autoDispose.family<LegalDocumentContent?, String>(
        (ref, slug) {
  return ref.watch(legalRepositoryProvider).getDocumentContent(slug);
});

/// 工具函数：记录用户对法律文档的同意
/// 调用方式：ref.read(recordConsentProvider)(slug, method, context)
/// 返回一个可直接 await 的 `Future<void>` 工厂
final recordConsentProvider = Provider<
    Future<void> Function({
      required String documentSlug,
      required String consentMethod,
      required String triggerContext,
    })>((ref) {
  return ({
    required String documentSlug,
    required String consentMethod,
    required String triggerContext,
  }) =>
      ref.read(legalRepositoryProvider).recordConsent(
            documentSlug: documentSlug,
            consentMethod: consentMethod,
            triggerContext: triggerContext,
          );
});

/// 工具函数：记录非同意类事件（prompted / declined / superseded）
/// 调用方式：ref.read(recordLegalEventProvider)(eventType, slug, details)
final recordLegalEventProvider = Provider<
    Future<void> Function({
      required String eventType,
      required String documentSlug,
      Map<String, dynamic>? details,
    })>((ref) {
  return ({
    required String eventType,
    required String documentSlug,
    Map<String, dynamic>? details,
  }) =>
      ref.read(legalRepositoryProvider).recordLegalEvent(
            eventType: eventType,
            documentSlug: documentSlug,
            details: details,
          );
});
