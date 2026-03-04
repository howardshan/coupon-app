import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 商家端 App 主容器，带底部 4-tab 导航
/// Tab 0: Dashboard（仪表盘）
/// Tab 1: Scan（核销扫码）
/// Tab 2: Orders（订单）
/// Tab 3: Me（账户/设置）
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/dashboard');
            case 1:
              context.go('/scan');
            case 2:
              context.go('/orders');
            case 3:
              context.go('/me');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Me',
          ),
        ],
      ),
    );
  }

  /// 根据当前路由路径计算高亮 tab 下标
  int _tabIndex(String location) {
    if (location.startsWith('/scan')) return 1;
    if (location.startsWith('/orders')) return 2;
    if (location.startsWith('/me')) return 3;
    return 0; // dashboard 为默认
  }
}
