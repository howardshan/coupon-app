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
import 'shared/providers/legal_provider.dart';
import 'shared/widgets/consent_barrier.dart';

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
// - 核销员(cashier): scan, orders → 2 tab
// - 客服(service): scan, orders, reviews → 3 tab
// - 店长(manager): 全部 → 5 tab
// - 门店老板/品牌管理员: 全部 → 5 tab
const _allTabs = [
  _TabItem(
    path: '/dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
    requiredPermission: 'analytics', // 核销员/客服没有此权限
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
    requiredPermission: 'reviews', // 核销员没有此权限
  ),
  _TabItem(
    path: '/me',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Me',
    requiredPermission: 'staff', // 核销员/客服没有此权限
  ),
];

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // 标记是否已弹出过 ConsentBarrier（避免重复弹出）
  bool _consentChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 仅在首次加载时触发一次 consent 检查
    // 使用 addPostFrameCallback 确保在第一帧完成后再弹窗，避免 context 尚未挂载
    if (!_consentChecked) {
      _consentChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkConsent();
      });
    }
  }

  /// 检查是否有待签法律文档，有则弹出 ConsentBarrier
  Future<void> _checkConsent() async {
    // 等待 provider 数据加载完成
    final pending = await ref.read(pendingConsentsProvider.future);
    if (pending.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ConsentBarrier(),
      );
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

    // 根据权限过滤可见 Tab
    final visibleTabs = _allTabs.where((tab) {
      if (tab.requiredPermission == null) return true;
      // 如果没有加载到权限信息（首次加载中），显示所有 tab
      if (permissions.isEmpty) return true;
      return permissions.contains(tab.requiredPermission);
    }).toList();

    // 如果没有可见 tab（极端情况），至少显示 Me
    if (visibleTabs.isEmpty) {
      visibleTabs.add(_allTabs.last);
    }

    final currentIndex = _tabIndex(location, visibleTabs);

    return Scaffold(
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
    );
  }
}
