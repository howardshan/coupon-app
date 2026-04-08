// 法律文档全屏展示页面（商家端）
// 从数据库加载文档内容并展示，可选显示底部"I Agree"按钮

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/legal_provider.dart';

// 商家端主题色（与 merchant_login_page 保持一致）
const _primaryOrange = Color(0xFFFF6B35);
const _textPrimary = Color(0xFF1A1A2E);
const _textSecondary = Color(0xFF6B7280);
const _textHint = Color(0xFF9CA3AF);
const _surfaceBg = Color(0xFFF8F9FA);
const _surfaceVariant = Color(0xFFF3F4F6);
const _errorColor = Color(0xFFEF4444);

/// 法律文档全屏展示页面
/// 接收 slug 参数，从数据库加载文档 HTML 内容并渲染
class LegalDocumentScreen extends ConsumerWidget {
  final String slug;
  final String title;

  /// 是否在底部显示"I Agree"按钮（用于同意流程）
  final bool showAgreeButton;

  /// 点击"I Agree"按钮的回调
  final VoidCallback? onAgree;

  const LegalDocumentScreen({
    super.key,
    required this.slug,
    required this.title,
    this.showAgreeButton = false,
    this.onAgree,
  });

  /// 简单去除 HTML 标签，将内容转为纯文本展示
  String _stripHtml(String html) {
    // 将常见 HTML 块级标签替换为换行，保留段落结构
    final withBreaks = html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n');

    // 去除所有剩余 HTML 标签
    final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), '');

    // 解码常见 HTML 实体
    final decoded = stripped
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // 压缩多余空行，最多保留两个换行
    return decoded.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(legalDocumentContentProvider(slug));

    return Scaffold(
      backgroundColor: _surfaceBg,
      appBar: AppBar(
        backgroundColor: _surfaceBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: _textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: docAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: _errorColor, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load document',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (doc) {
          // doc 可能为 null（provider 数据为空时），做保护处理
          if (doc == null) {
            return const Center(
              child: Text(
                'Document not available.',
                style: TextStyle(color: _textSecondary),
              ),
            );
          }

          // contentHtml 是 LegalDocumentContent 的 HTML 正文字段
          final plainText = _stripHtml(doc.contentHtml);

          return Column(
            children: [
              // 文档内容区域
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 版本号和发布日期元信息
                      _MetaInfoRow(
                        // version 是 int，转为 String 传给 _MetaInfoRow
                        version: doc.version.toString(),
                        publishedAt: doc.publishedAt,
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: _surfaceVariant),
                      const SizedBox(height: 20),

                      // 文档正文（可选中复制）
                      SelectableText(
                        plainText,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textPrimary,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 可选底部"I Agree"按钮
              if (showAgreeButton) ...[
                const Divider(height: 1, color: _surfaceVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: onAgree,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'I have read and agree to the $title',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 版本号与发布日期行
class _MetaInfoRow extends StatelessWidget {
  final String version;
  final DateTime? publishedAt;

  const _MetaInfoRow({
    required this.version,
    this.publishedAt,
  });

  @override
  Widget build(BuildContext context) {
    // 格式化日期，精确到月日年
    final dateStr = publishedAt == null
        ? null
        : '${publishedAt!.month}/${publishedAt!.day}/${publishedAt!.year}';

    return Row(
      children: [
        // 版本号徽章
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Version $version',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textSecondary,
            ),
          ),
        ),

        // 发布日期
        if (dateStr != null) ...[
          const SizedBox(width: 10),
          Text(
            'Effective $dateStr',
            style: const TextStyle(
              fontSize: 12,
              color: _textHint,
            ),
          ),
        ],
      ],
    );
  }
}
