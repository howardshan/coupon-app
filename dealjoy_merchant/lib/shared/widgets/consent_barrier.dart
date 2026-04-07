// 全屏同意拦截弹窗（商家端）
// 当检测到商家用户有未同意的法律文档时弹出，用户必须全部同意才能继续使用 App
// 退出登录逻辑：直接调用 Supabase.instance.client.auth.signOut() + go('/auth/login')

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/legal_provider.dart';
import 'legal_document_screen.dart';

// 商家端主题色常量
const _primaryOrange = Color(0xFFFF6B35);
const _textPrimary = Color(0xFF1A1A2E);
const _textSecondary = Color(0xFF6B7280);
const _surfaceBg = Color(0xFFF8F9FA);
const _surfaceVariant = Color(0xFFF3F4F6);
const _errorColor = Color(0xFFEF4444);

/// 全屏同意拦截弹窗
/// 商家必须同意所有待签文档才能关闭，拒绝则退出登录
class ConsentBarrier extends ConsumerStatefulWidget {
  const ConsentBarrier({super.key});

  @override
  ConsumerState<ConsentBarrier> createState() => _ConsentBarrierState();
}

class _ConsentBarrierState extends ConsumerState<ConsentBarrier> {
  /// 已勾选（已阅读）的文档 slug 集合
  final Set<String> _checkedSlugs = {};

  /// 正在提交同意中（防止重复点击）
  bool _isSubmitting = false;

  /// 全部勾选后才允许点击"I Agree to All"
  bool get _allChecked =>
      _checkedSlugs.isNotEmpty &&
      // 通过当前 provider 值判断是否全部勾选
      ref
          .read(pendingConsentsProvider)
          .valueOrNull
          ?.every((doc) => _checkedSlugs.contains(doc.slug)) ==
          true;

  /// 点击"I Agree to All" — 逐个记录同意，完成后刷新 provider
  Future<void> _handleAgreeAll(List<PendingConsent> pendingList) async {
    setState(() => _isSubmitting = true);

    try {
      final recordConsent = ref.read(recordConsentProvider);
      for (final doc in pendingList) {
        await recordConsent(
          documentSlug: doc.slug,
          consentMethod: 'checkbox',
          triggerContext: 'consent_barrier',
        );
      }
      // 刷新待同意列表，若已全部同意则弹窗将被上层移除
      ref.invalidate(pendingConsentsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record consent: $e'),
            backgroundColor: _errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 点击"Decline" — 弹出确认对话框，确认后退出登录
  Future<void> _handleDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          'If you decline, you will be signed out of your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _errorColor),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // 商家端退出登录：直接调用 Supabase signOut，然后跳转到登录页
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.go('/auth/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingConsentsProvider);

    return Dialog.fullscreen(
      backgroundColor: _surfaceBg,
      child: SafeArea(
        child: pendingAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: _primaryOrange),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load documents: $e',
                style: const TextStyle(color: _errorColor),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (pendingList) {
            // 若列表为空，外层应已关闭弹窗，此处显示加载态兜底
            if (pendingList.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: _primaryOrange),
              );
            }

            return Column(
              children: [
                // 顶部内容：logo、标题、说明
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // App 名称/Logo
                        const Text(
                          'DealJoy Merchant',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _primaryOrange,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 主标题
                        const Text(
                          'Updated Terms & Policies',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 副标题说明
                        const Text(
                          "We've updated the following documents. Please review and accept to continue using the app.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 待签文档列表
                        ...pendingList.map(
                          (doc) => _ConsentDocumentTile(
                            doc: doc,
                            isChecked: _checkedSlugs.contains(doc.slug),
                            onCheckedChanged: (checked) {
                              setState(() {
                                if (checked) {
                                  _checkedSlugs.add(doc.slug);
                                } else {
                                  _checkedSlugs.remove(doc.slug);
                                }
                              });
                            },
                            onViewTapped: () {
                              // 以只读模式推入文档页面，不显示 Agree 按钮
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => LegalDocumentScreen(
                                    slug: doc.slug,
                                    title: doc.title,
                                    showAgreeButton: false,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 底部操作区
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      const Divider(color: _surfaceVariant),
                      const SizedBox(height: 16),

                      // "I Agree to All" 主按钮，所有文档勾选后才可用
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              (_allChecked && !_isSubmitting)
                                  ? () => _handleAgreeAll(pendingList)
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryOrange,
                            disabledBackgroundColor:
                                _primaryOrange.withAlpha(100),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'I Agree to All',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // "Decline" 文字按钮
                      TextButton(
                        onPressed: _isSubmitting ? null : _handleDecline,
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 单条待签文档行
/// 显示标题、版本号、变更摘要，右侧有"View"按钮，左侧有 Checkbox
class _ConsentDocumentTile extends StatelessWidget {
  final PendingConsent doc;
  final bool isChecked;
  final ValueChanged<bool> onCheckedChanged;
  final VoidCallback onViewTapped;

  const _ConsentDocumentTile({
    required this.doc,
    required this.isChecked,
    required this.onCheckedChanged,
    required this.onViewTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChecked ? _primaryOrange : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 勾选框，表示用户已阅读
          Checkbox(
            value: isChecked,
            activeColor: _primaryOrange,
            onChanged: (val) => onCheckedChanged(val ?? false),
          ),

          // 文档信息
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题 + 版本号
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Color.fromARGB(25, 0xFF, 0x6B, 0x35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'v${doc.currentVersion}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 变更摘要（若存在）
                  if (doc.summaryOfChanges != null &&
                      doc.summaryOfChanges!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      doc.summaryOfChanges!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // "View" 按钮，只读查看文档
                  GestureDetector(
                    onTap: onViewTapped,
                    child: const Text(
                      'View',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _primaryOrange,
                        decoration: TextDecoration.underline,
                        decorationColor: _primaryOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
