import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../domain/providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  File? _pickedImage;
  String? _currentAvatarUrl;
  DateTime? _dateOfBirth;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final editState = ref.watch(profileEditProvider);
    final isLoading = editState.isLoading;

    // 初始化表单数据（只执行一次）
    userAsync.whenData((user) {
      if (!_initialized && user != null) {
        _nameCtrl.text = user.fullName ?? '';
        _bioCtrl.text = user.bio ?? '';
        _currentAvatarUrl = user.avatarUrl;
        _dateOfBirth = user.dateOfBirth;
        _initialized = true;
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: isLoading ? null : _save,
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 头像区域
              _buildAvatarSection(),
              const SizedBox(height: 32),

              // Display Name
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  hintText: 'Enter your name',
                  border: OutlineInputBorder(),
                ),
                maxLength: 32,
                validator: (v) {
                  if (v == null || v.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Bio
              TextFormField(
                controller: _bioCtrl,
                decoration: InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell us about yourself',
                  border: const OutlineInputBorder(),
                  counterText: '${_bioCtrl.text.length}/150',
                ),
                maxLength: 150,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Date of Birth（生日选择器）
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
                    firstDate: DateTime(1900),
                    lastDate: now,
                    helpText: 'SELECT YOUR DATE OF BIRTH',
                  );
                  if (picked != null) {
                    setState(() => _dateOfBirth = picked);
                  }
                },
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth',
                      hintText: 'MM/DD/YYYY',
                      prefixIcon: Icon(Icons.cake_outlined, size: 20),
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(
                      text: _dateOfBirth != null
                          ? '${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
                          : '',
                    ),
                    validator: (_) {
                      if (_dateOfBirth == null) {
                        return 'Date of birth is required';
                      }
                      final age = DateTime.now().difference(_dateOfBirth!).inDays ~/ 365;
                      if (age < 18) {
                        return 'You must be at least 18 years old';
                      }
                      return null;
                    },
                  ),
                ),
              ),
              // 未满 18 岁警告
              if (_dateOfBirth != null &&
                  DateTime.now().difference(_dateOfBirth!).inDays ~/ 365 < 18)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'You must be at least 18 years old to use Crunchy Plum.',
                          style: TextStyle(fontSize: 12, color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final hasNewImage = _pickedImage != null;
    final hasExistingAvatar = _currentAvatarUrl != null;

    return GestureDetector(
      onTap: _showImagePicker,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            backgroundImage: hasNewImage
                ? FileImage(_pickedImage!)
                : (hasExistingAvatar
                    ? CachedNetworkImageProvider(_currentAvatarUrl!)
                    : null) as ImageProvider?,
            child: (!hasNewImage && !hasExistingAvatar)
                ? Text(
                    (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : 'U')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 36,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Library'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xFile != null) {
      setState(() => _pickedImage = File(xFile.path));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // 如果生日有变化，先保存生日
    if (_dateOfBirth != null && _dateOfBirth != user.dateOfBirth) {
      try {
        await ref.read(profileRepositoryProvider).updateDateOfBirth(
          userId: user.id,
          dateOfBirth: _dateOfBirth!,
        );
      } catch (_) {
        // 不阻塞其他 profile 保存
      }
    }

    final success = await ref.read(profileEditProvider.notifier).saveProfile(
      userId: user.id,
      avatarFile: _pickedImage,
      displayName: _nameCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
    );

    if (!mounted) return;
    if (success) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile. Please try again.')),
      );
    }
  }
}
