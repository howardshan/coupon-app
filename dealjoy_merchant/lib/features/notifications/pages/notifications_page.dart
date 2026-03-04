// 商家通知列表页面
// 顶部：'Notifications' 标题 + 'Mark All Read' 按钮
// Tab：All / Unread（Tab 标签显示未读数量）
// 内容：通知列表（NotificationTile）+ 下拉刷新 + 加载更多
// 空状态：友好提示插画

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/notifications_provider.dart';
import '../widgets/notification_tile.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 监听 Tab 切换，更新筛选条件 Provider
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      // index 0 = All, index 1 = Unread Only
      ref.read(unreadOnlyFilterProvider.notifier).state =
          _tabController.index == 1;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unreadAsync  = ref.watch(unreadCountProvider);
    final unreadCount  = unreadAsync.value ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation:       0,
        centerTitle:     false,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontSize:   20,
            fontWeight: FontWeight.w700,
            color:      Color(0xFF1A1A1A),
          ),
        ),
        // Mark All Read 按钮（只在有未读时高亮）
        actions: [
          TextButton(
            onPressed: unreadCount > 0 ? _markAllRead : null,
            child: Text(
              'Mark All Read',
              style: TextStyle(
                color: unreadCount > 0
                    ? const Color(0xFFFF6B35)
                    : Colors.grey.shade400,
                fontWeight: FontWeight.w600,
                fontSize:   14,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller:       _tabController,
          labelColor:       const Color(0xFFFF6B35),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor:   const Color(0xFFFF6B35),
          indicatorWeight:  2.5,
          labelStyle:       const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
          tabs: [
            const Tab(text: 'All'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unread'),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    // Tab 标签上的未读数量 Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color:        const Color(0xFFFF6B35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),

      // TabBarView：全部通知 / 仅未读
      body: TabBarView(
        controller: _tabController,
        children: const [
          _NotificationsList(unreadOnly: false),
          _NotificationsList(unreadOnly: true),
        ],
      ),
    );
  }

  // 全部标记已读
  void _markAllRead() {
    ref.read(notificationsNotifierProvider.notifier).markAllRead();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:  Text('All notifications marked as read'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// =============================================================
// _NotificationsList — 通知列表（内部组件）
// 支持下拉刷新 + 无限滚动加载更多 + 空状态
// =============================================================
class _NotificationsList extends ConsumerStatefulWidget {
  const _NotificationsList({required this.unreadOnly});

  final bool unreadOnly;

  @override
  ConsumerState<_NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends ConsumerState<_NotificationsList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听滚动到底部，触发加载更多
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // 滚动到距底部 150px 时触发加载更多
  void _onScroll() {
    final maxScroll  = _scrollController.position.maxScrollExtent;
    final current    = _scrollController.position.pixels;
    if (current >= maxScroll - 150) {
      ref.read(notificationsNotifierProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsNotifierProvider);
    final notifier           = ref.read(notificationsNotifierProvider.notifier);

    return notificationsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
      ),

      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => notifier.refresh(),
      ),

      data: (allNotifications) {
        // 在 Tab 内部再过滤（避免切换 Tab 时重新请求网络，直接本地过滤）
        final notifications = widget.unreadOnly
            ? allNotifications.where((n) => !n.isRead).toList()
            : allNotifications;

        if (notifications.isEmpty) {
          return RefreshIndicator(
            color:     const Color(0xFFFF6B35),
            onRefresh: notifier.refresh,
            child:     SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child:   SizedBox(
                height: 500,
                child:  _EmptyState(unreadOnly: widget.unreadOnly),
              ),
            ),
          );
        }

        return RefreshIndicator(
          color:     const Color(0xFFFF6B35),
          onRefresh: notifier.refresh,
          child:     ListView.separated(
            controller:  _scrollController,
            physics:     const AlwaysScrollableScrollPhysics(),
            itemCount:   notifications.length + (notifier.hasMore ? 1 : 0),
            separatorBuilder: (context, i) => const Divider(
              height:  1,
              indent:  70,
              color:   Color(0xFFF0F0F0),
            ),
            itemBuilder: (context, index) {
              // 列表底部：加载更多指示器
              if (index == notifications.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child:   Center(
                    child: SizedBox(
                      width:  24,
                      height: 24,
                      child:  CircularProgressIndicator(
                        strokeWidth: 2,
                        color:       Color(0xFFFF6B35),
                      ),
                    ),
                  ),
                );
              }

              return NotificationTile(
                notification: notifications[index],
              );
            },
          ),
        );
      },
    );
  }
}

// =============================================================
// _EmptyState — 空状态提示（内部组件）
// =============================================================
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.unreadOnly});

  final bool unreadOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标占位（V1 使用 Material Icon，后续可替换插画）
            Container(
              width:  80,
              height: 80,
              decoration: BoxDecoration(
                color:        const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.notifications_none_outlined,
                size:  40,
                color: Color(0xFFBDBDBD),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              unreadOnly ? 'No Unread Notifications' : 'No Notifications Yet',
              style: const TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF424242),
              ),
            ),
            const SizedBox(height: 8),

            Text(
              unreadOnly
                  ? "You're all caught up! Check back later."
                  : 'New orders, redemptions, and updates\nwill appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color:    Color(0xFF9E9E9E),
                height:   1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// _ErrorView — 错误状态视图（内部组件）
// =============================================================
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String      message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size:  48,
              color: Color(0xFFBDBDBD),
            ),
            const SizedBox(height: 16),

            const Text(
              'Failed to load notifications',
              style: TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w600,
                color:      Color(0xFF424242),
              ),
            ),
            const SizedBox(height: 8),

            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
