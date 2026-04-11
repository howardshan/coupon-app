import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/providers/auth_provider.dart';
import '../../shared/providers/legal_provider.dart';
import '../../shared/widgets/consent_barrier.dart';
import '../theme/app_colors.dart';

/// 主 Scaffold：包含底部导航栏，并在启动时检查是否有待签法律文档
class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with WidgetsBindingObserver {
  /// 防止重复弹出 ConsentBarrier dialog 的标志
  bool _consentDialogShown = false;

  @override
  void initState() {
    super.initState();
    // 注册生命周期监听，App 回到前台时重新检查待签法律文档
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 从后台恢复到前台 → 强制重新拉取待签法律文档列表
    // 这样如果 Admin 在用户挂起 App 期间发布了新版本 ToS/Privacy 等，
    // 用户回到 App 立即看到 ConsentBarrier 弹窗
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(pendingConsentsProvider);
    }
  }

  int _locationToIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/chat')) return 1;
    if (location.startsWith('/cart')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 监听待签法律文档，有待签文档时弹出拦截 dialog
    final pendingAsync = ref.watch(pendingConsentsProvider);
    pendingAsync.whenData((consents) {
      if (consents.isNotEmpty && !_consentDialogShown) {
        _consentDialogShown = true;
        // 避免在 build 阶段直接调用 showDialog
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (_) => const ConsentBarrier(),
          ).then((_) {
            // dialog 关闭后重置标志，允许下次登录后再次检查
            if (mounted) {
              setState(() => _consentDialogShown = false);
            }
          });
        });
      }
    });

    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        height: 60,
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/home');
            case 1: context.go('/chat');
            case 2: context.go('/cart');
            case 3: context.go('/profile');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Deals',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// 邮箱未验证提示横幅
class _EmailVerificationBanner extends StatefulWidget {
  final WidgetRef ref;
  const _EmailVerificationBanner({required this.ref});

  @override
  State<_EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState extends State<_EmailVerificationBanner> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await widget.ref
          .read(authRepositoryProvider)
          .resendVerificationEmail();
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send verification email'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sent
                      ? 'Verification email sent! Check your inbox.'
                      : 'Please verify your email address.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              if (!_sent)
                TextButton(
                  key: const ValueKey('scaffold_resend_otp_btn'),
                  onPressed: _sending ? null : _resend,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resend',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
