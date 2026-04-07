// 法律文档 Riverpod Providers（商家端）
// 包含：数据模型、Repository、Providers
// 角色固定为 'merchant'，直接使用 Supabase.instance.client

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 商家端直接使用单例 client，不走 supabaseClientProvider
final _supabase = Supabase.instance.client;

// ─────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────

/// 待确认的法律文档（商家尚未同意的新版本）
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

/// 法律文档数据访问层（商家端）
class LegalRepository {
  /// 检查当前商家用户待同意的法律文档列表
  /// 调用 RPC: check_pending_consents(p_user_id, p_role)
  /// 角色固定为 'merchant'，若用户未登录则返回空列表
  Future<List<PendingConsent>> checkPendingConsents() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final result = await _supabase.rpc(
      'check_pending_consents',
      params: {
        'p_user_id': user.id,
        'p_role': 'merchant',
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
      // 占位符替换失败不阻塞展示
    }
    return doc;
  }

  /// 记录商家对指定法律文档的同意
  /// 调用 RPC: record_user_consent(...)
  Future<void> recordConsent({
    required String documentSlug,
    required String consentMethod,
    required String triggerContext,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // 获取平台信息（ios / android / other）
    String platform = 'other';
    try {
      if (Platform.isIOS) {
        platform = 'ios';
      } else if (Platform.isAndroid) {
        platform = 'android';
      }
    } catch (_) {
      // Web 或不支持 Platform 的环境
    }

    await _supabase.rpc(
      'record_user_consent',
      params: {
        'p_user_id': user.id,
        'p_document_slug': documentSlug,
        'p_actor_role': 'merchant',
        'p_consent_method': consentMethod,
        'p_trigger_context': triggerContext,
        'p_ip_address': null,
        'p_user_agent': null,
        'p_device_info': null,
        'p_app_version': '1.0.0',
        'p_platform': platform,
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
  return LegalRepository();
});

/// 当前商家用户待同意的法律文档列表
/// 调用 RPC: check_pending_consents
final pendingConsentsProvider = FutureProvider<List<PendingConsent>>((ref) {
  return ref.watch(legalRepositoryProvider).checkPendingConsents();
});

/// 按 slug 获取法律文档正文（FutureProvider.family，参数为 slug）
/// 调用 RPC: get_legal_document_content
final legalDocumentContentProvider =
    FutureProvider.family<LegalDocumentContent?, String>((ref, slug) {
  return ref.watch(legalRepositoryProvider).getDocumentContent(slug);
});

/// 工具函数：记录商家对法律文档的同意
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
