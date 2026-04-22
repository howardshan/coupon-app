// 设施管理页面
// 展示设施列表 + 新增/编辑/删除设施 + 图片上传

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../models/store_facility_model.dart';
import '../providers/facilities_provider.dart';
import '../providers/store_provider.dart';

// ============================================================
// StoreFacilitiesPage — 设施管理主页
// ============================================================
class StoreFacilitiesPage extends ConsumerWidget {
  const StoreFacilitiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facilitiesAsync = ref.watch(facilitiesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: const Color(0xFF333333),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Facilities & Services',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context, ref, null),
        backgroundColor: const Color(0xFFFF6B35),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: facilitiesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
        ),
        error: (e, _) => _ErrorView(
          error: e.toString(),
          onRetry: () => ref.read(facilitiesProvider.notifier).refresh(),
        ),
        data: (facilities) => _FacilitiesList(
          facilities: facilities,
          onAdd: () => _openForm(context, ref, null),
          onEdit: (f) => _openForm(context, ref, f),
          onDelete: (f) => _confirmDelete(context, ref, f),
          onQuickAdd: (type, name, isFree) => ref.read(facilitiesProvider.notifier).create(
            facilityType: type,
            name: name,
            isFree: isFree,
          ),
        ),
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref, StoreFacilityModel? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FacilityFormSheet(
        existing: existing,
        onSaved: (type, name, desc, imageUrl, capacity, isFree) async {
          final notifier = ref.read(facilitiesProvider.notifier);
          if (existing == null) {
            await notifier.create(
              facilityType: type,
              name: name,
              description: desc,
              imageUrl: imageUrl,
              capacity: capacity,
              isFree: isFree,
            );
          } else {
            await notifier.updateFacility(
              existing.id,
              facilityType: type,
              name: name,
              description: desc,
              imageUrl: imageUrl,
              capacity: capacity,
              isFree: isFree,
              clearImageUrl: imageUrl == null && existing.imageUrl != null,
              clearDescription: desc == null,
              clearCapacity: capacity == null,
            );
          }
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, StoreFacilityModel facility) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Facility'),
        content: Text('Remove "${facility.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref.read(facilitiesProvider.notifier).delete(facility.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Facility deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// 快捷预设定义（全局共用）
const _kPresets = [
  (type: 'wifi',         name: 'Free WiFi',              isFree: true),
  (type: 'parking',      name: 'Free Parking',            isFree: true),
  (type: 'parking',      name: 'Paid Parking',            isFree: false),
  (type: 'private_room', name: 'Private Dining Room',     isFree: false),
  (type: 'baby_chair',   name: 'Baby High Chair',         isFree: true),
  (type: 'large_table',  name: 'Large Group Table',       isFree: false),
  (type: 'no_smoking',   name: 'No Smoking Area',         isFree: true),
  (type: 'reservation',  name: 'Reservations Available',  isFree: true),
  (type: 'other',        name: 'Outdoor Seating',         isFree: true),
  (type: 'other',        name: 'Takeout Available',       isFree: true),
  (type: 'other',        name: 'Delivery Available',      isFree: true),
  (type: 'other',        name: 'Catering Service',        isFree: false),
];

// ============================================================
// 设施列表（顶部预设 + 已添加列表）
// ============================================================
class _FacilitiesList extends StatelessWidget {
  const _FacilitiesList({
    required this.facilities,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onQuickAdd,
  });

  final List<StoreFacilityModel> facilities;
  final VoidCallback onAdd;
  final void Function(StoreFacilityModel) onEdit;
  final void Function(StoreFacilityModel) onDelete;
  final void Function(String type, String name, bool isFree) onQuickAdd;

  @override
  Widget build(BuildContext context) {
    // 过滤掉已添加过的同名预设
    final addedNames = facilities.map((f) => f.name.toLowerCase()).toSet();
    final availablePresets = _kPresets
        .where((p) => !addedNames.contains(p.name.toLowerCase()))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 快捷预设区 ──────────────────────────────────────────
        if (availablePresets.isNotEmpty) ...[
          const Text(
            'Common Facilities  —  tap to add instantly',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF999999),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availablePresets.map((p) {
              return GestureDetector(
                onTap: () => onQuickAdd(p.type, p.name, p.isFree),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFCCB0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 14, color: Color(0xFFFF6B35)),
                      const SizedBox(width: 4),
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  facilities.isEmpty ? 'Or create custom' : 'Added',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // ── 已添加的设施列表 ──────────────────────────────────
        if (facilities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No custom facilities yet. Tap + to create one.',
              style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...List.generate(facilities.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FacilityTile(
              facility: facilities[i],
              onEdit: () => onEdit(facilities[i]),
              onDelete: () => onDelete(facilities[i]),
            ),
          )),
      ],
    );
  }
}

// ============================================================
// 单个设施卡片
// ============================================================
class _FacilityTile extends StatelessWidget {
  const _FacilityTile({
    required this.facility,
    required this.onEdit,
    required this.onDelete,
  });

  final StoreFacilityModel facility;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 图片缩略图（如有）
          if (facility.imageUrl != null) ...[
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: facility.imageUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 80,
                  height: 80,
                  color: const Color(0xFFF0F0F0),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 80,
                  height: 80,
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.broken_image_outlined, color: Color(0xFFCCCCCC)),
                ),
              ),
            ),
          ] else ...[
            // 无图片时显示 type 图标
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4EF),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
              ),
              child: Icon(facility.icon, color: const Color(0xFFFF6B35), size: 32),
            ),
          ],
          const SizedBox(width: 12),
          // 文字区域
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          facility.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Free badge
                      if (facility.isFree) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Free',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    StoreFacilityModel.typeLabel(facility.facilityType),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B35)),
                  ),
                  if (facility.description != null && facility.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      facility.description!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (facility.capacity != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Capacity: ${facility.capacity}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 操作按钮
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF888888)),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFCC4444)),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ============================================================
// 新增/编辑表单 BottomSheet
// ============================================================
class _FacilityFormSheet extends ConsumerStatefulWidget {
  const _FacilityFormSheet({
    required this.existing,
    required this.onSaved,
  });

  final StoreFacilityModel? existing;
  final Future<void> Function(
    String type,
    String name,
    String? description,
    String? imageUrl,
    int? capacity,
    bool isFree,
  ) onSaved;

  @override
  ConsumerState<_FacilityFormSheet> createState() => _FacilityFormSheetState();
}

class _FacilityFormSheetState extends ConsumerState<_FacilityFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedType;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _capacityCtrl;
  late bool _isFree;

  // 图片相关
  String? _imageUrl;       // 当前图片 URL（已保存或刚上传的）
  bool _isUploadingImage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    _selectedType = f?.facilityType ?? 'other';
    _nameCtrl = TextEditingController(text: f?.name ?? '');
    _descCtrl = TextEditingController(text: f?.description ?? '');
    _capacityCtrl = TextEditingController(
      text: f?.capacity != null ? f!.capacity.toString() : '',
    );
    _isFree = f?.isFree ?? true;
    _imageUrl = f?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 90,
    );
    if (picked == null) return;

    // 裁剪为 4:3（匹配用户端 FacilityCard 展示比例）
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
      compressQuality: 85,
      maxWidth: 800,
      maxHeight: 600,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: const Color(0xFFFF6B35),
          statusBarColor: const Color(0xFFCC4E1E),
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null) return;

    final storeAsync = ref.read(storeProvider);
    final merchantId = storeAsync.valueOrNull?.id ?? '';
    if (merchantId.isEmpty) return;

    setState(() => _isUploadingImage = true);
    try {
      final service = ref.read(storeServiceProvider);
      final url = await service.uploadFacilityImage(
        merchantId: merchantId,
        file: XFile(cropped.path),
      );
      setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _removeImage() => setState(() => _imageUrl = null);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final capacity = int.tryParse(_capacityCtrl.text.trim());
      final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
      await widget.onSaved(
        _selectedType,
        _nameCtrl.text.trim(),
        desc,
        _imageUrl,
        capacity,
        _isFree,
      );
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existing == null ? 'Facility added' : 'Facility updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖动把手
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 标题
            Text(
              isEdit ? 'Edit Facility' : 'Add Facility',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),

            // 新增时显示快捷预设
            if (!isEdit) ...[
              const SizedBox(height: 16),
              const Text(
                'Quick Presets',
                style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
              ),
              const SizedBox(height: 8),
              _buildPresets(),
              const Divider(height: 24),
            ] else
              const SizedBox(height: 20),

            // Facility Type 下拉
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: _inputDecoration('Facility Type'),
              items: StoreFacilityModel.allTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(StoreFacilityModel.typeLabel(type)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
            ),
            const SizedBox(height: 14),

            // Name（必填）
            TextFormField(
              controller: _nameCtrl,
              decoration: _inputDecoration('Name *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),

            // Description（可选）
            TextFormField(
              controller: _descCtrl,
              decoration: _inputDecoration('Description (optional)'),
              maxLines: 2,
              maxLength: 200,
            ),
            const SizedBox(height: 14),

            // 容量 + Is Free 横排
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _capacityCtrl,
                    decoration: _inputDecoration('Capacity (optional)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Switch(
                        value: _isFree,
                        activeColor: const Color(0xFFFF6B35),
                        onChanged: (v) => setState(() => _isFree = v),
                      ),
                      const Text(
                        'Free',
                        style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 图片区域
            _buildImageSection(),
            const SizedBox(height: 24),

            // Save 按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save Changes' : 'Add Facility',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 快捷预设列表（常见设施，点击即填充表单字段）
  static const _presets = [
    (type: 'wifi',         name: 'Free WiFi',           isFree: true),
    (type: 'parking',      name: 'Free Parking',         isFree: true),
    (type: 'parking',      name: 'Paid Parking',         isFree: false),
    (type: 'private_room', name: 'Private Dining Room',  isFree: false),
    (type: 'baby_chair',   name: 'Baby High Chair',      isFree: true),
    (type: 'large_table',  name: 'Large Group Table',    isFree: false),
    (type: 'no_smoking',   name: 'No Smoking Area',      isFree: true),
    (type: 'reservation',  name: 'Reservations Available', isFree: true),
    (type: 'other',        name: 'Outdoor Seating',      isFree: true),
    (type: 'other',        name: 'Takeout Available',    isFree: true),
    (type: 'other',        name: 'Delivery Available',   isFree: true),
    (type: 'other',        name: 'Catering Service',     isFree: false),
  ];

  Widget _buildPresets() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((p) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedType = p.type;
              _nameCtrl.text = p.name;
              _isFree = p.isFree;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4EF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFCCB0)),
            ),
            child: Text(
              p.name,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFFF6B35),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImageSection() {
    if (_imageUrl != null) {
      // 已有图片
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Photo',
            style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: _imageUrl!,
                  width: 120,
                  height: 90,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 120,
                    height: 90,
                    color: const Color(0xFFF0F0F0),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _removeImage,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 上传按钮
    return GestureDetector(
      onTap: _isUploadingImage ? null : _pickImage,
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD), style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(8),
          color: const Color(0xFFFAFAFA),
        ),
        child: _isUploadingImage
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF6B35),
                  strokeWidth: 2,
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: Color(0xFFBBBBBB), size: 28),
                  SizedBox(height: 4),
                  Text(
                    'Add Photo (optional)',
                    style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFFF6B35)),
      ),
    );
  }
}

// ============================================================
// 错误视图
// ============================================================
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(error, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
