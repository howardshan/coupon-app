// 头图模式选择器
// 让商家选择客户端店铺详情页的头图展示方式：单图轮播 / 三图并排

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/store_info.dart';
import '../providers/store_provider.dart';

class HeaderStyleSelector extends ConsumerStatefulWidget {
  const HeaderStyleSelector({super.key});

  @override
  ConsumerState<HeaderStyleSelector> createState() =>
      _HeaderStyleSelectorState();
}

class _HeaderStyleSelectorState extends ConsumerState<HeaderStyleSelector> {
  // 本地编辑状态
  late String _style;
  late List<String> _selectedPhotos;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider).valueOrNull;
    _style = store?.headerPhotoStyle ?? 'single';
    _selectedPhotos = List<String>.from(store?.headerPhotos ?? []);
  }

  // 可选的照片池：cover + storefront + environment
  List<StorePhoto> _getAvailablePhotos(StoreInfo store) {
    return [
      ...store.coverPhotos,
      ...store.storefrontPhotos,
      ...store.environmentPhotos,
    ];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(storeProvider.notifier).updateHeaderStyle(
            headerPhotoStyle: _style,
            headerPhotos: _selectedPhotos,
          );
      _dirty = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Header style saved'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider).valueOrNull;
    if (store == null) return const SizedBox.shrink();

    final availablePhotos = _getAvailablePhotos(store);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模式选择按钮
        _buildModeSelector(),
        const SizedBox(height: 16),

        // 预览
        _buildPreview(availablePhotos),
        const SizedBox(height: 16),

        // Triple 模式下选择 3 张照片
        if (_style == 'triple') ...[
          const Text(
            'Select 3 photos for triple header:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 10),
          _buildPhotoSelector(availablePhotos),
          const SizedBox(height: 16),
        ],

        // 保存按钮
        if (_dirty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const ValueKey('header_style_save_btn'),
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Header Style',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'single',
          icon: Icon(Icons.view_carousel_outlined, size: 18),
          label: Text('Single Photo'),
        ),
        ButtonSegment(
          value: 'triple',
          icon: Icon(Icons.view_column_outlined, size: 18),
          label: Text('Three Photos'),
        ),
      ],
      selected: {_style},
      onSelectionChanged: (selected) {
        setState(() {
          _style = selected.first;
          _dirty = true;
          // 切换到 triple 模式时，自动选前 3 张可用照片（如果还没选）
          if (_style == 'triple' && _selectedPhotos.length < 3) {
            final store = ref.read(storeProvider).valueOrNull;
            if (store != null) {
              final available = _getAvailablePhotos(store);
              _selectedPhotos = available
                  .take(3)
                  .map((p) => p.url)
                  .toList();
            }
          }
        });
      },
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFFFF0E8);
          }
          return Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFFF6B35);
          }
          return const Color(0xFF666666);
        }),
      ),
    );
  }

  // 预览区域
  Widget _buildPreview(List<StorePhoto> availablePhotos) {
    if (_style == 'single') {
      // Single 模式预览：展示第一张 cover 照片
      final coverUrl = availablePhotos.isNotEmpty ? availablePhotos.first.url : null;
      return _buildPreviewContainer(
        height: 140,
        child: coverUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: coverUrl,
                  width: double.infinity,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              )
            : _buildEmptyPreview('Upload cover photos first'),
      );
    }

    // Triple 模式预览：三张图并排
    if (_selectedPhotos.length < 3) {
      return _buildPreviewContainer(
        height: 100,
        child: _buildEmptyPreview('Select 3 photos below'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 100,
        child: Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : 1,
                  right: i == 2 ? 0 : 1,
                ),
                child: CachedNetworkImage(
                  imageUrl: _selectedPhotos[i],
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPreviewContainer({required double height, required Widget child}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFFF5F5F5),
      ),
      child: child,
    );
  }

  Widget _buildEmptyPreview(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
      ),
    );
  }

  // 照片选择网格（Triple 模式专用）
  Widget _buildPhotoSelector(List<StorePhoto> availablePhotos) {
    if (availablePhotos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFDDCC)),
        ),
        child: const Text(
          'No photos available. Upload cover, storefront, or environment photos first.',
          style: TextStyle(fontSize: 13, color: Color(0xFFFF6B35)),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: availablePhotos.map((photo) {
        final isSelected = _selectedPhotos.contains(photo.url);
        final selectionIndex = _selectedPhotos.indexOf(photo.url);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                // 取消选择
                _selectedPhotos.remove(photo.url);
              } else if (_selectedPhotos.length < 3) {
                // 选中（最多 3 张）
                _selectedPhotos.add(photo.url);
              }
              _dirty = true;
            });
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: photo.url,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              // 选中遮罩 + 编号
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFF6B35),
                        width: 2.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF6B35),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${selectionIndex + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 未选中时半透明遮罩（如果已选满 3 张）
              if (!isSelected && _selectedPhotos.length >= 3)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              // 照片类型标签
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    photo.type.displayLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
