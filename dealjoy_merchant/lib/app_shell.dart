// 商家端 App 主容器，带底部导航
// 根据当前用户权限动态显示/隐藏 Tab：
// - 核销员(cashier): Scan + Orders (2 tab)
// - 客服(service): Scan + Orders + Me (3 tab)
// - 店长(manager): Dashboard + Scan + Orders + Me (4 tab)
// - 门店老板/品牌管理员: 全部 (4 tab)
// 启动时检查待签法律文档，有则弹出 ConsentBarrier

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/store/providers/store_provider.dart';
import 'router/app_router.dart';
import 'shared/providers/legal_provider.dart';
import 'shared/widgets/consent_barrier.dart';

/// 根据 roleType 推算默认权限（用于 storeProvider 尚未加载时）
List<String> _defaultPermissionsForRole(String? roleType) {
  switch (roleType) {
    case 'staff_cashier':
    case 'staff_trainee':
      return ['scan', 'orders'];
    case 'staff_finance':
      return ['earnings'];
    case 'staff_regional_manager':
      return ['analytics', 'scan', 'orders', 'reviews', 'staff', 'earnings'];
    case 'staff_manager':
      return ['analytics', 'scan', 'orders', 'reviews', 'staff', 'earnings'];
    default:
      // store_owner / brand_admin / unknown → 显示全部
      return ['analytics', 'scan', 'orders', 'reviews', 'staff', 'earnings', 'brand'];
  }
}

/// 定义一个 Tab 项（路由 + 图标 + 标签 + 所需权限）
class _TabItem {
  const _TabItem({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.requiredPermission,
  });

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  // 如果为 null，所有角色都显示
  final String? requiredPermission;
}

// 所有可能的 Tab（按顺序）
// 权限控制:
// - 核销员(cashier): scan, orders, profile → 3 tab
// - 客服(service): scan, orders, reviews → 3 tab
// - 店长(manager): 全部 → 5 tab
// - 门店老板/品牌管理员: 全部 → 5 tab
// 特殊权限标记：'!staff' 表示「没有 staff 权限时才显示」（cashier/trainee 专用）
const _allTabs = [
  _TabItem(
    path: '/dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
    requiredPermission: 'analytics',
  ),
  _TabItem(
    path: '/scan',
    icon: Icons.qr_code_scanner_outlined,
    selectedIcon: Icons.qr_code_scanner,
    label: 'Scan',
    requiredPermission: 'scan',
  ),
  _TabItem(
    path: '/orders',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Orders',
    requiredPermission: 'orders',
  ),
  _TabItem(
    path: '/reviews',
    icon: Icons.rate_review_outlined,
    selectedIcon: Icons.rate_review,
    label: 'Reviews',
    requiredPermission: 'reviews',
  ),
  _TabItem(
    path: '/me',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Me',
    requiredPermission: 'staff',
  ),
  // cashier/trainee 专用 Profile tab（有 staff 权限的角色用 Me tab）
  _TabItem(
    path: '/staff/profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Profile',
    requiredPermission: '!staff',
  ),
];

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  // 当前是否有 ConsentBarrier dialog 正在显示（避免重复弹出）
  bool _consentDialogVisible = false;

  // 供 BackButtonListener 回调读取，build() 每次更新
  List<_TabItem> _visibleTabs = [];
  int _currentIndex = 0;


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
    // 如果此时 Admin 已发布新版本 Merchant Agreement / ToS 等强制重签文档，
    // 商家回到 App 会立即看到 ConsentBarrier 弹窗
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(pendingConsentsProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkConsent();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首次进入 AppShell 时触发一次 consent 检查
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkConsent();
    });
  }

  /// 检查是否有待签法律文档，有则弹出 ConsentBarrier
  Future<void> _checkConsent() async {
    if (_consentDialogVisible) return; // 已在显示，跳过
    // 等待 provider 数据加载完成
    final pending = await ref.read(pendingConsentsProvider.future);
    if (pending.isNotEmpty && mounted && !_consentDialogVisible) {
      _consentDialogVisible = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ConsentBarrier(),
      );
      _consentDialogVisible = false;
    }
  }

  /// 根据当前路由路径计算高亮 tab 下标
  int _tabIndex(String location, List<_TabItem> tabs) {
    for (var i = 0; i < tabs.length; i++) {
      if (location.startsWith(tabs[i].path)) return i;
    }
    return 0; // 默认第一个
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    // 获取当前门店信息中的权限列表
    final storeAsync = ref.watch(storeProvider);
    final permissions = storeAsync.valueOrNull?.permissions ?? [];

    // 权限未加载时用 roleType 推算默认权限，避免短暂显示全部 Tab
    final effectivePermissions = permissions.isEmpty
        ? _defaultPermissionsForRole(MerchantStatusCache.roleType)
        : permissions;

    // 根据权限过滤可见 Tab
    // '!xxx' 表示「没有 xxx 权限时才显示」
    final visibleTabs = _allTabs.where((tab) {
      final req = tab.requiredPermission;
      if (req == null) return true;
      if (req.startsWith('!')) return !effectivePermissions.contains(req.substring(1));
      return effectivePermissions.contains(req);
    }).toList();

    // 如果没有可见 tab（极端情况），至少显示 Me
    if (visibleTabs.isEmpty) {
      visibleTabs.add(_allTabs.last);
    }

    final currentIndex = _tabIndex(location, visibleTabs);

    // 每次 build 更新缓存值，供 BackButtonListener 回调使用
    _visibleTabs = visibleTabs;
    _currentIndex = currentIndex;

    return BackButtonListener(
      // go_router 还有子页面可 pop 时返回 false，让 go_router 自己处理
      // 在 root tab 且非首页时跳首页，在首页时返回 false 让系统退出 App
      onBackButtonPressed: () async {
        if (GoRouter.of(context).canPop()) return false;
        if (_currentIndex > 0 && _visibleTabs.isNotEmpty) {
          context.go(_visibleTabs[0].path);
          return true;
        }
        return false; // 首页 → 系统处理（退出 App）
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (i) {
            if (i < visibleTabs.length) {
              context.go(visibleTabs[i].path);
            }
          },
          destinations: visibleTabs
              .map((tab) => NavigationDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
