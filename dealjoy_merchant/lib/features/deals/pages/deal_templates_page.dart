// V2.2 Deal 模板管理页面
// 品牌管理员可创建模板，一键发布到多个门店

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../store/providers/store_provider.dart';
import '../models/deal_template.dart';
import '../providers/deals_provider.dart';

class DealTemplatesPage extends ConsumerWidget {
  const DealTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(dealTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deal Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/deals/templates/create'),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load templates',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text(e.toString(),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.read(dealTemplatesProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return _EmptyState(
              onCreateTap: () => context.push('/deals/templates/create'),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(dealTemplatesProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: templates.length,
              itemBuilder: (context, index) {
                return _TemplateCard(template: templates[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

// 空状态提示
class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_all, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Deal Templates Yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a template to quickly publish deals across all your stores.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add),
              label: const Text('Create Template'),
            ),
          ],
        ),
      ),
    );
  }
}

// 模板卡片
class _TemplateCard extends ConsumerWidget {
  final DealTemplate template;
  const _TemplateCard({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTemplateActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusChip(isActive: template.isActive),
                ],
              ),
              const SizedBox(height: 8),

              // 价格信息
              Row(
                children: [
                  Text(
                    '\$${template.discountPrice.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.orange[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (template.originalPrice > 0)
                    Text(
                      '\$${template.originalPrice.toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                      ),
                    ),
                  const Spacer(),
                  if (template.category.isNotEmpty)
                    Chip(
                      label: Text(template.category),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 发布信息
              Row(
                children: [
                  Icon(Icons.storefront, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${template.publishedStoreCount} stores published',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (template.customizedStoreCount > 0) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.edit_note, size: 16, color: Colors.blue[400]),
                    const SizedBox(width: 4),
                    Text(
                      '${template.customizedStoreCount} customized',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.blue[400]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 模板操作菜单
  void _showTemplateActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.publish),
              title: const Text('Publish to Stores'),
              subtitle: const Text('Select stores to create deals'),
              onTap: () {
                Navigator.pop(ctx);
                _showPublishDialog(context, ref);
              },
            ),
            if (template.publishedStoreCount > 0)
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync to All Stores'),
                subtitle: const Text('Update non-customized deals'),
                onTap: () {
                  Navigator.pop(ctx);
                  _syncTemplate(context, ref);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Template'),
              onTap: () {
                Navigator.pop(ctx);
                // TODO: 导航到编辑页面
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red[400]),
              title: Text('Delete Template',
                  style: TextStyle(color: Colors.red[400])),
              onTap: () {
                Navigator.pop(ctx);
                _deleteTemplate(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 发布到门店弹窗
  void _showPublishDialog(BuildContext context, WidgetRef ref) {
    final brandStoresAsync = ref.read(brandStoresProvider);
    final stores = brandStoresAsync.valueOrNull ?? [];

    if (stores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stores found in your brand')),
      );
      return;
    }

    // 已发布的门店 ID 集合
    final publishedIds =
        template.linkedStores.map((s) => s.merchantId).toSet();
    // 可发布的门店（未发布过的）
    final availableStores =
        stores.where((s) => !publishedIds.contains(s.id)).toList();

    if (availableStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('All stores already have this deal published')),
      );
      return;
    }

    final selectedIds = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Publish to Stores'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableStores.length,
              itemBuilder: (ctx, index) {
                final store = availableStores[index];
                final isSelected = selectedIds.contains(store.id);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        selectedIds.add(store.id);
                      } else {
                        selectedIds.remove(store.id);
                      }
                    });
                  },
                  title: Text(store.name),
                  subtitle: Text(store.address ?? ''),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedIds.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _publishToStores(
                          context, ref, selectedIds.toList());
                    },
              child: Text('Publish (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );
  }

  // 执行发布
  Future<void> _publishToStores(
    BuildContext context,
    WidgetRef ref,
    List<String> merchantIds,
  ) async {
    try {
      final result = await ref
          .read(dealTemplatesProvider.notifier)
          .publishTemplate(template.id, merchantIds);
      final published = result['published'] as int? ?? 0;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Published to $published stores')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e')),
        );
      }
    }
  }

  // 同步模板
  Future<void> _syncTemplate(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(dealTemplatesProvider.notifier)
          .syncTemplate(template.id);
      final synced = result['synced'] as int? ?? 0;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced $synced stores')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  // 删除模板
  Future<void> _deleteTemplate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template?'),
        content: const Text(
          'This will only remove the template. Published deals at each store will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(dealTemplatesProvider.notifier)
            .deleteTemplate(template.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template deleted')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }
}

// 状态标签
class _StatusChip extends StatelessWidget {
  final bool isActive;
  const _StatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.green[300]! : Colors.grey[300]!,
        ),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 12,
          color: isActive ? Colors.green[700] : Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
