// 全屏同意拦截弹窗
// 当检测到用户有未同意的法律文档时弹出，用户必须全部同意才能继续使用 App

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/domain/providers/auth_provider.dart';
import '../providers/legal_provider.dart';
import 'legal_document_screen.dart';

/// 全屏同意拦截弹窗
/// 用户必须同意所有待签文档才能关闭，拒绝则退出登录
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

  /// 已经写过 consent_prompted 事件的 slug 集合（防止重复写审计日志）
  final Set<String> _promptedLoggedSlugs = {};

  /// 全部勾选后才允许点击"I Agree to All"
  bool get _allChecked =>
      _checkedSlugs.isNotEmpty &&
      // 通过当前 provider 值判断是否全部勾选
      ref
          .read(pendingConsentsProvider)
          .valueOrNull
          ?.every((doc) => _checkedSlugs.contains(doc.slug)) ==
          true;

  /// 写入 consent_prompted 审计事件（证明"我们在此时向用户展示了此文档"）
  /// 对每个 slug 只写一次，避免重复日志
  void _logPromptedEvents(List<PendingConsent> pendingList) {
    final recordEvent = ref.read(recordLegalEventProvider);
    for (final doc in pendingList) {
      if (_promptedLoggedSlugs.contains(doc.slug)) continue;
      _promptedLoggedSlugs.add(doc.slug);
      // fire-and-forget：不阻塞 UI
      recordEvent(
        eventType: 'consent_prompted',
        documentSlug: doc.slug,
        details: {
          'trigger_context': 'consent_barrier',
          'document_version': doc.currentVersion,
        },
      ).catchError((_) {
        // 审计日志失败不影响用户使用，但允许重试
        _promptedLoggedSlugs.remove(doc.slug);
      });
    }
  }

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
            backgroundColor: AppColors.error,
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
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // 为所有当前待签文档写 consent_declined 审计事件（证明用户明确拒绝）
      final pendingList =
          ref.read(pendingConsentsProvider).valueOrNull ?? const [];
      final recordEvent = ref.read(recordLegalEventProvider);
      for (final doc in pendingList) {
        try {
          await recordEvent(
            eventType: 'consent_declined',
            documentSlug: doc.slug,
            details: {
              'trigger_context': 'consent_barrier',
              'document_version': doc.currentVersion,
              'action': 'sign_out',
            },
          );
        } catch (_) {
          // 审计日志失败不阻塞登出流程
        }
      }

      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).signOut();
      // 退出登录后关闭全屏弹窗，让 go_router 的 auth 守卫将用户重定向至登录页
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingAsync = ref.watch(pendingConsentsProvider);

    return Dialog.fullscreen(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: pendingAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to load documents: $e',
                style: const TextStyle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (pendingList) {
            // 若列表为空，说明所有文档已同意 → 自动关闭弹窗
            // （之前只 invalidate provider 但不关闭对话框，会卡在 loading 状态）
            if (pendingList.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context, rootNavigator: true).pop();
                }
              });
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            // 首次拿到待签列表 → 写 consent_prompted 审计事件（fire-and-forget）
            // 在 postFrame 调用避免 build 阶段触发网络请求
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _logPromptedEvents(pendingList);
            });

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
                          'Crunchy Plum',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
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
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 副标题说明
                        const Text(
                          "We've updated the following documents. Please review and accept to continue using the app.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
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
                      const Divider(color: AppColors.surfaceVariant),
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
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor:
                                AppColors.primary.withAlpha(100),
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
                            color: AppColors.textSecondary,
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
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChecked ? AppColors.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 勾选框，表示用户已阅读
          Checkbox(
            value: isChecked,
            activeColor: AppColors.primary,
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
                            color: AppColors.textPrimary,
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
                          color: AppColors.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'v${doc.currentVersion}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
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
                        color: AppColors.textSecondary,
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
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.primary,
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
