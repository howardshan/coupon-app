// 门店 Deal 确认页面
// 门店老板/店长收到 pending_store_confirmation 后进入此页面
// 功能：
//   1. 展示 Deal 信息（标题、品牌、价格）
//   2. 自动从 menu_items 按名称模糊匹配，检测菜品是否存在
//   3. 菜品存在 → 显示单价、折扣%、Accept/Decline 按钮
//   4. 菜品不存在 → 提示并显示 Add to Menu 入口，添加后再 Accept
//   5. 48 小时倒计时提示（从 deal_applicable_stores.created_at 计算）

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../menu/models/menu_item.dart';

// ============================================================
// StoreDealConfirmPage — 门店确认 brand_multi_store Deal
// ============================================================
class StoreDealConfirmPage extends StatefulWidget {
  const StoreDealConfirmPage({
    super.key,
    required this.dealId,
    required this.dealTitle,
    required this.dealPrice,
    required this.brandName,
  });

  /// Deal ID
  final String dealId;

  /// Deal 标题（用于显示和菜品名称模糊匹配）
  final String dealTitle;

  /// Deal 价格（美元）
  final double dealPrice;

  /// 品牌名称
  final String brandName;

  @override
  State<StoreDealConfirmPage> createState() => _StoreDealConfirmPageState();
}

class _StoreDealConfirmPageState extends State<StoreDealConfirmPage> {
  static const _primaryColor = Color(0xFFFF6B35);

  final _supabase = Supabase.instance.client;

  // 加载状态
  bool _isLoading = true;
  String? _errorMessage;

  // deal_applicable_stores 记录状态
  String _confirmStatus = 'pending_store_confirmation';
  DateTime? _requestedAt;

  // 菜品匹配结果
  MenuItem? _matchedItem;
  bool _menuChecked = false;

  // 操作中状态
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --------------------------------------------------------
  // 加载数据：查 deal_applicable_stores + 菜品匹配
  // --------------------------------------------------------
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // 获取当前门店 merchant_id
      final merchantRow = await _supabase
          .from('merchants')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (merchantRow == null) throw Exception('Merchant not found');
      final merchantId = merchantRow['id'] as String;

      // 查 deal_applicable_stores 获取该门店的确认记录
      final storeRow = await _supabase
          .from('deal_applicable_stores')
          .select('status, created_at')
          .eq('deal_id', widget.dealId)
          .eq('store_id', merchantId)
          .maybeSingle();

      if (storeRow != null) {
        _confirmStatus = storeRow['status'] as String? ?? 'pending_store_confirmation';
        final createdAtStr = storeRow['created_at'] as String?;
        _requestedAt = createdAtStr != null ? DateTime.parse(createdAtStr) : null;
      }

      // 从 menu_items 按名称模糊匹配 dealTitle 中的关键词
      // 取标题首个词（去掉数量前缀如 "2-Person"）作为关键词
      final keyword = _extractKeyword(widget.dealTitle);
      if (keyword.isNotEmpty) {
        final menuRows = await _supabase
            .from('menu_items')
            .select('id, merchant_id, name, price, image_url, category, category_id, '
                'recommendation_count, is_signature, sort_order, status, created_at')
            .eq('merchant_id', merchantId)
            .eq('status', 'active')
            .ilike('name', '%$keyword%')
            .limit(1);

        if (menuRows.isNotEmpty) {
          _matchedItem = MenuItem.fromJson(menuRows.first);
        }
      }
      _menuChecked = true;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --------------------------------------------------------
  // 从标题提取匹配关键词（取首个有意义的词）
  // 例：'2-Person BBQ Set for 2' → 'BBQ'
  // --------------------------------------------------------
  String _extractKeyword(String title) {
    // 移除数量前缀（如 "2-Person "）
    final cleaned = title.replaceAll(RegExp(r'^\d+[-\s]\w+\s+'), '').trim();
    // 取第一个词
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    // 过滤掉太短的词
    return parts.firstWhere((p) => p.length > 2, orElse: () => parts.first);
  }

  // --------------------------------------------------------
  // 计算距离 48 小时截止还剩多久
  // --------------------------------------------------------
  Duration? get _timeRemaining {
    if (_requestedAt == null) return null;
    final deadline = _requestedAt!.add(const Duration(hours: 48));
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String get _countdownText {
    final rem = _timeRemaining;
    if (rem == null) return '';
    if (rem == Duration.zero) return 'Deadline passed';
    final hours = rem.inHours;
    final minutes = rem.inMinutes % 60;
    return '${hours}h ${minutes}m remaining';
  }

  // --------------------------------------------------------
  // 调用 Edge Function 执行 accept / decline
  // --------------------------------------------------------
  Future<void> _confirm(String action) async {
    setState(() => _isSubmitting = true);
    try {
      final response = await _supabase.functions.invoke(
        'merchant-deals/${widget.dealId}/store-confirm',
        method: HttpMethod.patch,
        body: {
          'action': action,
          'menu_item_id': _matchedItem?.id,
        },
      );

      if (response.status != 200) {
        final data = response.data;
        String msg = 'Request failed (${response.status})';
        if (data is Map && data.containsKey('error')) {
          msg = data['error'] as String;
        }
        throw Exception(msg);
      }

      if (!mounted) return;

      // 成功后刷新状态
      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accept'
                ? 'Deal accepted! It will go live after platform review.'
                : 'Deal declined.',
          ),
          backgroundColor: action == 'accept'
              ? const Color(0xFF4CAF50)
              : const Color(0xFF757575),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --------------------------------------------------------
  // Build
  // --------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF333333)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Confirm Deal',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildError()
              : _buildContent(),
    );
  }

  // --------------------------------------------------------
  // 错误状态
  // --------------------------------------------------------
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFE53935)),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------
  // 主内容
  // --------------------------------------------------------
  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 信息卡片
          _buildDealInfoCard(),
          const SizedBox(height: 16),

          // 48 小时倒计时提示
          if (_requestedAt != null) _buildCountdownBanner(),
          if (_requestedAt != null) const SizedBox(height: 16),

          // 当前状态显示
          if (_confirmStatus != 'pending_store_confirmation')
            _buildStatusBanner()
          else ...[
            // 菜品检测结果 + 操作按钮
            _buildMenuMatchSection(),
            const SizedBox(height: 16),
            if (_menuChecked) _buildActionButtons(),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // Deal 信息卡片
  // --------------------------------------------------------
  Widget _buildDealInfoCard() {
    // 计算折扣百分比（Deal 价格相对于菜品原价）
    final itemPrice = _matchedItem?.price;
    final discountPct = (itemPrice != null && itemPrice > 0 && widget.dealPrice < itemPrice)
        ? ((1 - widget.dealPrice / itemPrice) * 100).round()
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 品牌标签
          Row(
            children: [
              const Icon(Icons.store_outlined, size: 14, color: Color(0xFF999999)),
              const SizedBox(width: 4),
              Text(
                widget.brandName,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Deal 标题
          Text(
            widget.dealTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),

          // 价格区域
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${widget.dealPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _primaryColor,
                ),
              ),
              if (itemPrice != null) ...[
                const SizedBox(width: 8),
                Text(
                  '\$${itemPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
              if (discountPct != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$discountPct% OFF',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // 48 小时倒计时横幅
  // --------------------------------------------------------
  Widget _buildCountdownBanner() {
    final rem = _timeRemaining;
    final isUrgent = rem != null && rem.inHours < 12;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUrgent
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUrgent
              ? const Color(0xFFF57C00)
              : const Color(0xFF66BB6A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: isUrgent ? const Color(0xFFF57C00) : const Color(0xFF388E3C),
          ),
          const SizedBox(width: 8),
          Text(
            'Response deadline: $_countdownText',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isUrgent ? const Color(0xFFF57C00) : const Color(0xFF388E3C),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // 当前状态横幅（已处理的记录）
  // --------------------------------------------------------
  Widget _buildStatusBanner() {
    final isAccepted = _confirmStatus == 'active' || _confirmStatus == 'accepted';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAccepted
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted
              ? const Color(0xFF66BB6A)
              : const Color(0xFFBDBDBD),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isAccepted ? Icons.check_circle : Icons.cancel_outlined,
            color: isAccepted
                ? const Color(0xFF388E3C)
                : const Color(0xFF757575),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAccepted ? 'Deal Accepted' : 'Deal Declined',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isAccepted
                        ? const Color(0xFF388E3C)
                        : const Color(0xFF757575),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isAccepted
                      ? 'This deal will go live at your location after platform review.'
                      : 'You have declined this deal for your location.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // 菜品匹配检测区域
  // --------------------------------------------------------
  Widget _buildMenuMatchSection() {
    if (!_menuChecked) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 2),
        ),
      );
    }

    if (_matchedItem != null) {
      // 找到匹配菜品
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Color(0xFF4CAF50)),
                SizedBox(width: 6),
                Text(
                  'Menu item found',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _matchedItem!.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
                Text(
                  _matchedItem!.price != null
                      ? '\$${_matchedItem!.price!.toStringAsFixed(2)}'
                      : 'No price set',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'This item is in your menu. You can accept the deal to make it available at your location.',
              style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
          ],
        ),
      );
    } else {
      // 未找到匹配菜品
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFCC80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFFF8F00)),
                SizedBox(width: 6),
                Text(
                  'Item not found in your menu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF8F00),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'This item doesn\'t exist in your menu yet. '
              'You can add it first, then come back to accept the deal. '
              'Or you may decline if your location doesn\'t carry this item.',
              style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 12),
            // 跳转到菜单管理页面（Add to Menu）
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // 导航到菜单管理页面，用户添加菜品后返回此页自动刷新
                  Navigator.of(context).pushNamed('/menu').then((_) {
                    if (mounted) _loadData();
                  });
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add to Menu'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'After adding the item to your menu, tap the refresh button or reopen this page to accept.',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
        ),
      );
    }
  }

  // --------------------------------------------------------
  // Accept / Decline 操作按钮
  // --------------------------------------------------------
  Widget _buildActionButtons() {
    return Column(
      children: [
        // Accept 按钮
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : () => _confirm('accept'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFCCBC),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Accept Deal',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 10),

        // Decline 按钮
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _isSubmitting ? null : () => _showDeclineDialog(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF757575),
              side: const BorderSide(color: Color(0xFFBDBDBD)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Decline',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------
  // Decline 二次确认对话框
  // --------------------------------------------------------
  void _showDeclineDialog() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this deal?'),
        content: const Text(
          'This deal will not be available at your location. '
          'Customers will not be able to purchase it here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF666666))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              _confirm('decline');
            },
            child: const Text('Decline',
                style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
  }
}
