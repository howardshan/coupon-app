// 门店 Deal 确认页面
// 门店老板/店长收到 pending_store_confirmation 后进入此页面
// 功能：
//   1. 展示 Deal 完整信息（标题、品牌、价格、描述、菜品、图片）
//   2. 自动从 menu_items 按名称模糊匹配，检测菜品是否存在
//   3. 所有菜品存在 → 隐藏警告，直接显示 Accept/Decline
//   4. 菜品不存在 → 提示并显示 Add to Menu 入口
//   5. 48 小时倒计时提示（从 deal_applicable_stores.created_at 计算）

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../menu/models/menu_item.dart';
import '../../store/services/store_service.dart';
import '../providers/deals_provider.dart';

// ============================================================
// StoreDealConfirmPage — 门店确认 brand_multi_store Deal
// ============================================================
class StoreDealConfirmPage extends ConsumerStatefulWidget {
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
  ConsumerState<StoreDealConfirmPage> createState() => _StoreDealConfirmPageState();
}

class _StoreDealConfirmPageState extends ConsumerState<StoreDealConfirmPage> {
  static const _primaryColor = Color(0xFFFF6B35);

  final _supabase = Supabase.instance.client;

  // 加载状态
  bool _isLoading = true;
  String? _errorMessage;

  // 当前门店 merchant_id（用于传给 Edge Function header）
  String? _merchantId;

  // deal_applicable_stores 记录状态
  String _confirmStatus = 'pending_store_confirmation';
  DateTime? _requestedAt;

  // 完整 deal 信息（从 DB 加载）
  Map<String, dynamic>? _dealData;

  // 菜品匹配结果
  MenuItem? _matchedItem;
  bool _menuChecked = false;

  // 多菜品匹配：deal 内所有菜品 vs 门店 menu
  List<String> _dealDishes = [];
  List<String> _unmatchedDishes = [];

  // 门店自己的原价（根据菜品价格×数量汇总）
  double? _storeOriginalPrice;

  // 操作中状态
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --------------------------------------------------------
  // 加载数据：查 deal 完整信息 + deal_applicable_stores + 菜品匹配
  // --------------------------------------------------------
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // 使用当前选中的门店 ID（品牌管理员通过 StoreSelector 切换后持久化的值）
      // 不能用 `merchants WHERE user_id` 因为品牌管理员管理多店，那样只会返回主门店
      final activeMerchantId = StoreService.globalActiveMerchantId;
      String merchantId;
      if (activeMerchantId != null && activeMerchantId.isNotEmpty) {
        merchantId = activeMerchantId;
      } else {
        // fallback：如果 globalActiveMerchantId 还没初始化
        final merchantRow = await _supabase
            .from('merchants')
            .select('id')
            .eq('user_id', userId)
            .maybeSingle();
        if (merchantRow == null) throw Exception('Merchant not found');
        merchantId = merchantRow['id'] as String;
      }
      _merchantId = merchantId;

      // 查询 deal 完整信息
      final dealRow = await _supabase
          .from('deals')
          .select('title, description, original_price, discount_price, '
              'discount_label, image_urls, dishes, package_contents, '
              'usage_notes, usage_days, category, merchant_hours, '
              'refund_policy, stock_limit, expires_at')
          .eq('id', widget.dealId)
          .maybeSingle();

      _dealData = dealRow;

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

      // 解析菜品名称列表
      _dealDishes = [];
      if (dealRow != null) {
        final rawDishes = dealRow['dishes'] as List? ?? [];
        if (rawDishes.isNotEmpty) {
          _dealDishes = rawDishes.map((e) => e.toString()).toList();
        } else {
          // fallback: 从 package_contents 按行拆分
          final pc = dealRow['package_contents'] as String? ?? '';
          if (pc.isNotEmpty) {
            _dealDishes = pc
                .split(RegExp(r'[\n,;]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
      }

      // 获取门店所有 active 菜品
      final allMenuRows = await _supabase
          .from('menu_items')
          .select('id, merchant_id, name, price, image_url, category, category_id, '
              'recommendation_count, is_signature, sort_order, status, created_at')
          .eq('merchant_id', merchantId)
          .eq('status', 'active')
          // 门店确认价仅针对已定价且在售菜品
          .not('price', 'is', null);

      // 构建 menu 名称→价格映射（用于匹配和计算门店原价）
      final menuMap = <String, double>{};
      for (final row in (allMenuRows as List)) {
        final name = (row['name'] as String? ?? '').toLowerCase();
        final price = (row['price'] as num?)?.toDouble() ?? 0;
        if (name.isNotEmpty) menuMap[name] = price;
      }

      // 逐个匹配 deal 菜品（用纯名称匹配）
      _unmatchedDishes = [];
      _storeOriginalPrice = null;
      double totalStorePrice = 0;
      bool allMatched = true;

      if (_dealDishes.isNotEmpty) {
        for (final dish in _dealDishes) {
          final pureName = _extractDishName(dish).toLowerCase();
          final qty = _extractDishQuantity(dish);

          // 模糊匹配：menu 中任一名称包含菜品纯名称，或菜品纯名称包含 menu 名称
          double? matchedPrice;
          for (final entry in menuMap.entries) {
            if (entry.key.contains(pureName) || pureName.contains(entry.key)) {
              matchedPrice = entry.value;
              break;
            }
          }

          if (matchedPrice == null) {
            _unmatchedDishes.add(dish);
            allMatched = false;
          } else {
            totalStorePrice += matchedPrice * qty;
          }
        }
        // 仅当所有菜品都匹配时才设置门店原价
        if (allMatched) {
          _storeOriginalPrice = totalStorePrice;
        }
      }

      // 兼容旧逻辑：如果 deal 没有 dishes 数据，fallback 用标题关键词匹配
      if (_dealDishes.isEmpty) {
        final keyword = _extractKeyword(widget.dealTitle);
        if (keyword.isNotEmpty) {
          final menuRows = await _supabase
              .from('menu_items')
              .select('id, merchant_id, name, price, image_url, category, category_id, '
                  'recommendation_count, is_signature, sort_order, status, created_at')
              .eq('merchant_id', merchantId)
              .eq('status', 'active')
              .not('price', 'is', null)
              .ilike('name', '%$keyword%')
              .limit(1);

          if (menuRows.isNotEmpty) {
            _matchedItem = MenuItem.fromJson(menuRows.first);
          }
        }
      } else {
        // 有 dishes 数据时，用第一个匹配到的菜品作为 _matchedItem
        if (_unmatchedDishes.length < _dealDishes.length) {
          for (final row in allMenuRows) {
            final menuName = (row['name'] as String? ?? '').toLowerCase();
            final matched = _dealDishes.any((d) {
              final dLower = _extractDishName(d).toLowerCase();
              return menuName.contains(dLower) || dLower.contains(menuName);
            });
            if (matched) {
              _matchedItem = MenuItem.fromJson(row);
              break;
            }
          }
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
  // --------------------------------------------------------
  String _extractKeyword(String title) {
    final cleaned = title.replaceAll(RegExp(r'^\d+[-\s]\w+\s+'), '').trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    return parts.firstWhere((p) => p.length > 2, orElse: () => parts.first);
  }

  // --------------------------------------------------------
  // 从菜品字符串提取数量（默认 1）
  // 例："2× Spicy Cilli Pork Instense @14.95" → 2
  // --------------------------------------------------------
  int _extractDishQuantity(String raw) {
    // 先去掉 bullet 前缀再匹配数量
    final cleaned = raw.replaceAll(RegExp(r'^[\s•\-]+'), '');
    final match = RegExp(r'^(\d+)\s*[×xX]').firstMatch(cleaned);
    return match != null ? int.tryParse(match.group(1)!) ?? 1 : 1;
  }

  // --------------------------------------------------------
  // 从菜品字符串提取纯名称（去掉 bullet、数量前缀和价格后缀）
  // 例："• 2× Spicy Cilli Pork Instense @14.95" → "Spicy Cilli Pork Instense"
  // --------------------------------------------------------
  String _extractDishName(String raw) {
    // 1. 先去掉前缀的 "• " 或 "- " 或空格
    var name = raw.replaceAll(RegExp(r'^[\s•\-]+'), '');
    // 2. 去掉数量前缀：数字 + ×/x/X + 空格
    name = name.replaceAll(RegExp(r'^\d+\s*[×xX]\s*'), '');
    // 3. 去掉后缀：@价格
    name = name.replaceAll(RegExp(r'\s*@\s*[\d,.]+\s*$'), '');
    return name.trim();
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
  // 传 X-Merchant-Id header 确保 resolveAuth 使用正确的门店
  // --------------------------------------------------------
  Future<void> _confirm(String action) async {
    setState(() => _isSubmitting = true);
    try {
      final response = await _supabase.functions.invoke(
        'merchant-deals/${widget.dealId}/store-confirm',
        method: HttpMethod.patch,
        headers: {
          if (_merchantId != null) 'X-Merchant-Id': _merchantId!,
        },
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

      // 成功后刷新本页状态 + dashboard 的 pending 计数
      await _loadData();
      ref.invalidate(pendingStoreDealsProvider);

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
              key: const ValueKey('deal_confirm_retry_btn'),
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
          // Deal 信息卡片（含完整详情）
          _buildDealInfoCard(),
          const SizedBox(height: 16),

          // Deal 详情（描述、菜品列表、使用须知等）
          if (_dealData != null) _buildDealDetailSection(),
          if (_dealData != null) const SizedBox(height: 16),

          // 48 小时倒计时提示（仅待确认状态显示）
          if (_requestedAt != null && _confirmStatus == 'pending_store_confirmation') _buildCountdownBanner(),
          if (_requestedAt != null && _confirmStatus == 'pending_store_confirmation') const SizedBox(height: 16),

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
  // Deal 信息卡片（标题 + 价格 + 图片）
  // --------------------------------------------------------
  Widget _buildDealInfoCard() {
    // 优先使用门店自己的原价（根据菜品价格计算），fallback 用 deal 表里的原价
    final originalPrice = _storeOriginalPrice ?? (_dealData?['original_price'] as num?)?.toDouble();
    final discountPrice = (_dealData?['discount_price'] as num?)?.toDouble() ?? widget.dealPrice;
    final discountLabel = _dealData?['discount_label'] as String? ?? '';
    final imageUrls = List<String>.from(_dealData?['image_urls'] as List? ?? []);

    // 计算折扣百分比
    final discountPct = (originalPrice != null && originalPrice > 0 && discountPrice < originalPrice)
        ? ((1 - discountPrice / originalPrice) * 100).round()
        : null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deal 图片（如果有）
          if (imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: imageUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: const Color(0xFFF0F0F0),
                    child: const Center(
                      child: Icon(Icons.image, size: 40, color: Color(0xFFBDBDBD)),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: const Color(0xFFF0F0F0),
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 40, color: Color(0xFFBDBDBD)),
                    ),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 品牌标签
                Row(
                  children: [
                    const Icon(Icons.store_outlined, size: 14, color: Color(0xFF999999)),
                    const SizedBox(width: 4),
                    // brandName 可能较长，用 Flexible 防止溢出
                    Flexible(
                      child: Text(
                        widget.brandName,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Deal 标题
                Text(
                  _dealData?['title'] as String? ?? widget.dealTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),

                // 价格区域（Flexible 保护原价文本，防止三段同时显示时溢出）
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${discountPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _primaryColor,
                      ),
                    ),
                    if (originalPrice != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '\$${originalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF999999),
                            decoration: TextDecoration.lineThrough,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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
                          discountLabel.isNotEmpty ? discountLabel : '$discountPct% OFF',
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
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // Deal 详情区域（描述、菜品列表、使用须知）
  // --------------------------------------------------------
  Widget _buildDealDetailSection() {
    final description = _dealData?['description'] as String? ?? '';
    final packageContents = _dealData?['package_contents'] as String? ?? '';
    final usageNotes = _dealData?['usage_notes'] as String? ?? '';
    final merchantHours = _dealData?['merchant_hours'] as String? ?? '';
    final refundPolicy = _dealData?['refund_policy'] as String? ?? '';
    final category = _dealData?['category'] as String? ?? '';
    final stockLimit = _dealData?['stock_limit'] as int? ?? 0;
    final expiresAtStr = _dealData?['expires_at'] as String?;
    final usageDays = List<String>.from(_dealData?['usage_days'] as List? ?? []);

    // 如果没有任何详情信息，不显示
    if (description.isEmpty && _dealDishes.isEmpty && packageContents.isEmpty &&
        usageNotes.isEmpty) {
      return const SizedBox.shrink();
    }

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
          const Text(
            'Deal Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),

          // 描述
          if (description.isNotEmpty) ...[
            Text(
              description,
              style: const TextStyle(fontSize: 14, color: Color(0xFF555555), height: 1.5),
            ),
            const SizedBox(height: 12),
          ],

          // 分类
          if (category.isNotEmpty) ...[
            _buildDetailRow(Icons.category_outlined, 'Category', category),
            const SizedBox(height: 8),
          ],

          // 菜品/套餐内容
          if (_dealDishes.isNotEmpty) ...[
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.restaurant_menu, size: 16, color: Color(0xFF666666)),
                SizedBox(width: 6),
                Text(
                  'Included Items',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...(_dealDishes.map((dish) => Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 4),
              child: Row(
                children: [
                  const Text('•  ', style: TextStyle(color: Color(0xFF999999))),
                  Expanded(
                    child: Text(
                      dish,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                    ),
                  ),
                ],
              ),
            ))),
            const SizedBox(height: 12),
          ] else if (packageContents.isNotEmpty) ...[
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.restaurant_menu, 'Package Contents', packageContents),
            const SizedBox(height: 12),
          ],

          // 使用须知
          if (usageNotes.isNotEmpty) ...[
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.info_outline, 'Usage Notes', usageNotes),
            const SizedBox(height: 8),
          ],

          // 使用时段
          if (usageDays.isNotEmpty) ...[
            _buildDetailRow(Icons.calendar_today, 'Available Days', usageDays.join(', ')),
            const SizedBox(height: 8),
          ],

          // 营业时间
          if (merchantHours.isNotEmpty) ...[
            _buildDetailRow(Icons.access_time, 'Hours', merchantHours),
            const SizedBox(height: 8),
          ],

          // 库存
          if (stockLimit > 0) ...[
            _buildDetailRow(Icons.inventory_2_outlined, 'Stock Limit', '$stockLimit'),
            const SizedBox(height: 8),
          ],

          // 有效期
          if (expiresAtStr != null) ...[
            _buildDetailRow(
              Icons.event,
              'Expires',
              _formatDate(expiresAtStr),
            ),
            const SizedBox(height: 8),
          ],

          // 退款政策
          if (refundPolicy.isNotEmpty) ...[
            _buildDetailRow(Icons.shield_outlined, 'Refund Policy', refundPolicy),
          ],
        ],
      ),
    );
  }

  // 详情行：图标 + 标签 + 值
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF999999)),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 格式化日期
  String _formatDate(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr);
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return isoStr;
    }
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
          // Expanded 防止倒计时文本过长时溢出
          Expanded(
            child: Text(
              'Response deadline: $_countdownText',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isUrgent ? const Color(0xFFF57C00) : const Color(0xFF388E3C),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
    final isDeclined = _confirmStatus == 'declined';
    return Column(
      children: [
        Container(
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
        ),
        // declined 状态显示重新 approve 按钮
        if (isDeclined) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSubmitting ? null : () => _confirm('accept'),
              icon: const Icon(Icons.refresh, size: 16),
              label: _isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reconsider & Accept'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: const BorderSide(color: _primaryColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
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

    // 有 dishes 数据且全部匹配 → 所有菜品都在 menu 里，不显示警告
    final allDishesMatched = _dealDishes.isNotEmpty && _unmatchedDishes.isEmpty;

    if (allDishesMatched) {
      // 所有菜品都匹配 → 不显示任何匹配区域，直接让用户操作
      return const SizedBox.shrink();
    }

    // fallback 模式（无 dishes 数据）且找到了匹配菜品
    if (_dealDishes.isEmpty && _matchedItem != null) {
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
    }

    // 有未匹配的菜品 或 完全没找到匹配
    return _buildUnmatchedWarning();
  }

  // --------------------------------------------------------
  // 未匹配菜品警告卡片
  // --------------------------------------------------------
  Widget _buildUnmatchedWarning() {
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
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFFF8F00)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _unmatchedDishes.isNotEmpty
                      ? '${_unmatchedDishes.length} item(s) not found in your menu'
                      : 'Item not found in your menu',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF8F00),
                  ),
                ),
              ),
            ],
          ),
          // 显示具体未匹配的菜品，每个带单独的 Add 按钮
          if (_unmatchedDishes.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_unmatchedDishes.map((dish) {
              final pureName = _extractDishName(dish);
              return Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.close, size: 14, color: Color(0xFFFF8F00)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dish,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: TextButton.icon(
                        onPressed: () {
                          context.push('/store/menu/create', extra: pureName).then((_) {
                            if (mounted) _loadData();
                          });
                        },
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            })),
          ],
          const SizedBox(height: 10),
          const Text(
            'These items don\'t exist in your menu yet. '
            'You can add them first, then come back to accept the deal. '
            'Or you may decline if your location doesn\'t carry these items.',
            style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 8),
          const Text(
            'After adding the items to your menu, tap the refresh button or reopen this page to accept.',
            style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
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
            key: const ValueKey('deal_confirm_accept_btn'),
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
