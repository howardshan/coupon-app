// 证件上传组件
// 显示证件类型名称、上传按钮、已上传文件的预览缩略图

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/merchant_application.dart';

// ============================================================
// DocumentUploadTile — 单个证件上传行
// ============================================================
class DocumentUploadTile extends StatelessWidget {
  const DocumentUploadTile({
    super.key,
    required this.documentType,
    required this.uploadedDocument,
    required this.onFilePicked,
    this.isLoading = false,
    this.isHighlighted = false,
  });

  /// 证件类型
  final DocumentType documentType;

  /// 已上传的证件（null 表示未上传）
  final MerchantDocument? uploadedDocument;

  /// 用户选择文件后的回调（传入本地文件路径）
  final ValueChanged<String> onFilePicked;

  /// 是否正在上传（显示 loading indicator）
  final bool isLoading;

  /// 审核被拒时高亮显示该字段（红色边框）
  final bool isHighlighted;

  static const _primaryOrange = Color(0xFFFF6B35);
  static const _errorRed = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final isUploaded = uploadedDocument?.isUploaded ?? false;
    final hasLocalFile = uploadedDocument?.localPath != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // 被拒字段显示红色边框，已上传显示绿色，未上传显示灰色
          color: isHighlighted
              ? _errorRed
              : isUploaded
                  ? Colors.green.shade400
                  : const Color(0xFFE0E0E0),
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 左侧：预览缩略图或占位图标
            _buildThumbnail(hasLocalFile),
            const SizedBox(width: 12),

            // 中间：证件名称 + 状态文字
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    documentType.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUploaded
                        ? 'Uploaded'
                        : hasLocalFile
                            ? 'Uploading...'
                            : documentType.imageOnly
                                ? 'Tap to upload image'
                                : 'Tap to upload image or PDF',
                    style: TextStyle(
                      fontSize: 12,
                      color: isUploaded
                          ? Colors.green.shade600
                          : const Color(0xFF9E9E9E),
                    ),
                  ),
                  // 审核被拒时显示错误提示
                  if (isHighlighted)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Document needs attention',
                        style: TextStyle(
                          fontSize: 11,
                          color: _errorRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 右侧：上传按钮或 loading
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _primaryOrange,
                ),
              )
            else
              _UploadButton(
                isUploaded: isUploaded,
                imageOnly: documentType.imageOnly,
                onFilePicked: onFilePicked,
              ),
          ],
        ),
      ),
    );
  }

  // 构建左侧缩略图
  Widget _buildThumbnail(bool hasLocalFile) {
    // 如果有本地路径，显示本地图片预览
    if (hasLocalFile && uploadedDocument?.localPath != null) {
      final path = uploadedDocument!.localPath!;
      final isPdf = path.toLowerCase().endsWith('.pdf');

      if (isPdf) {
        // PDF 显示图标占位
        return _thumbnailContainer(
          child: const Icon(Icons.picture_as_pdf, color: _errorRed, size: 28),
        );
      }

      return _thumbnailContainer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (context, e, stackTrace) => const Icon(
              Icons.broken_image,
              color: Color(0xFF9E9E9E),
              size: 28,
            ),
          ),
        ),
      );
    }

    // 未上传时显示占位图标
    return _thumbnailContainer(
      child: Icon(
        documentType.imageOnly ? Icons.photo_camera : Icons.upload_file,
        color: const Color(0xFFBDBDBD),
        size: 28,
      ),
    );
  }

  // 缩略图容器（统一尺寸和背景）
  Widget _thumbnailContainer({required Widget child}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: child),
    );
  }
}

// ============================================================
// 上传按钮（私有组件）
// ============================================================
class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.isUploaded,
    required this.imageOnly,
    required this.onFilePicked,
  });

  final bool isUploaded;
  final bool imageOnly;
  final ValueChanged<String> onFilePicked;

  static const _primaryOrange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPickerOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUploaded
              ? Colors.green.shade50
              : _primaryOrange.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUploaded ? Colors.green.shade400 : _primaryOrange,
          ),
        ),
        child: Text(
          isUploaded ? 'Change' : 'Upload',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isUploaded ? Colors.green.shade700 : _primaryOrange,
          ),
        ),
      ),
    );
  }

  // 弹出选择器菜单（相机 / 相册 / Files）
  void _showPickerOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 相机拍照（仅图片类型或通用类型）
              ListTile(
                leading: const Icon(Icons.camera_alt, color: _primaryOrange),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromCamera();
                },
              ),
              // 从相册选择
              ListTile(
                leading:
                    const Icon(Icons.photo_library, color: _primaryOrange),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromGallery();
                },
              ),
              // PDF 文件（非 imageOnly 类型）
              if (!imageOnly)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf,
                      color: Color(0xFFD32F2F)),
                  title: const Text('Upload PDF'),
                  subtitle: const Text('PDF files supported'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickPdf();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null) onFilePicked(picked.path);
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null) onFilePicked(picked.path);
  }

  // PDF 文件选取（image_picker 不支持 PDF；
  // 生产中集成 file_picker 包后替换此实现）
  Future<void> _pickPdf() async {
    // 当前版本仅支持图片格式，PDF 选取为占位实现
    // 后续替换为: FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'])
  }
}
