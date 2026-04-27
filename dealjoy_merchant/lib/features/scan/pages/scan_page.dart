// 扫码核销主页面
// 顶部两个 Tab: "Scan QR" / "Enter Code"
// QR Tab: MobileScanner 实时扫描
// Enter Code Tab: 文字输入框 + Verify 按钮

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/coupon_info.dart';
import '../providers/scan_provider.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // MobileScanner 控制器 — 用于暂停/恢复相机
  MobileScannerController? _cameraController;

  // 防止同一帧内多次触发扫码回调
  bool _isProcessing = false;

  // 手动输入 Tab 相关
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _manualCodeFocus = FocusNode();
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initCamera();

    // 切换 Tab 时，重置扫码处理标志；回到扫码 Tab 时收起键盘
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _isProcessing = false;
      }
      if (!_tabController.indexIsChanging && _tabController.index == 0) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      // 切到手动输入 Tab 时暂停相机节省电量
      if (_tabController.index == 1) {
        _cameraController?.stop();
      } else {
        _cameraController?.start();
      }
    });
  }

  void _initCamera() {
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cameraController?.dispose();
    _manualCodeFocus.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // =============================================================
  // 扫码回调处理
  // =============================================================
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final code = barcode!.rawValue!;
    _isProcessing = true;

    // 暂停相机，防止重复扫描
    _cameraController?.stop();

    await _verifyCoupon(code);

    // 如果验证失败，恢复扫描
    if (mounted) {
      _isProcessing = false;
      _cameraController?.start();
    }
  }

  // =============================================================
  // 验证券码（扫码和手动输入共用）
  // =============================================================
  Future<void> _verifyCoupon(String code) async {
    await ref.read(scanNotifierProvider.notifier).verify(code);

    if (!mounted) return;
    final state = ref.read(scanNotifierProvider);

    state.when(
      data: (couponInfo) {
        if (couponInfo != null) {
          // 与 go_router 子路由一致，避免 Material 栈残留导致「再扫一次」仍显示确认页
          context.push('/scan/verify', extra: couponInfo);
        }
      },
      error: (e, _) {
        final message = e is ScanException ? e.message : 'Verification failed.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      },
      loading: () {},
    );
  }

  // =============================================================
  // 手动输入验证
  // =============================================================
  Future<void> _verifyManual() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isVerifying = true);
    final code = _codeController.text.trim();

    await _verifyCoupon(code);

    if (mounted) setState(() => _isVerifying = false);
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(scanNotifierProvider);
    final isLoading = scanState.isLoading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Scan Voucher',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // 核销历史入口
          IconButton(
            onPressed: () => context.push('/scan/history'),
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'Redemption History',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF6B35),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          tabs: const [
            Tab(text: 'Scan QR'),
            Tab(text: 'Enter Code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ——— Tab 1: QR 扫码 ———
          _buildQrTab(isLoading),
          // ——— Tab 2: 手动输入 ———
          _buildManualTab(isLoading),
        ],
      ),
    );
  }

  // =============================================================
  // QR 扫码 Tab
  // =============================================================
  Widget _buildQrTab(bool isLoading) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 相机视图（全屏）
        if (_cameraController != null)
          MobileScanner(
            controller: _cameraController!,
            onDetect: _onDetect,
          ),

        // 扫码取景框遮罩
        _ScanOverlay(isLoading: isLoading),

        // 加载中覆盖层
        if (isLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF6B35),
              ),
            ),
          ),

        // 底部手动输入提示
        Positioned(
          bottom: 48,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(1);
              },
              child: Text(
                'Enter Code Manually',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),

        // 顶部手电筒按钮
        Positioned(
          top: 16,
          right: 16,
          child: _TorchButton(controller: _cameraController),
        ),
      ],
    );
  }

  // =============================================================
  // 手动输入 Tab
  // =============================================================
  Widget _buildManualTab(bool isLoading) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Enter Voucher Code',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Type or paste the 16-digit voucher code from the customer\'s app. (auto-format: 4-4-4-4)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 24),

              // 券码输入框
              TextFormField(
                key: const ValueKey('scan_code_field'),
                controller: _codeController,
                focusNode: _manualCodeFocus,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 19, // 16 字符 + 3 个横杠
                inputFormatters: const [_CouponCodeDashInputFormatter()],
                onFieldSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. AB12-CD34-EF56-GH78',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFFFF6B35), width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.red.shade400, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a voucher code.';
                  }
                  final normalized = value.replaceAll('-', '').trim();
                  // 支持 16 位数字（旧码）或 16 位字母数字混合（新码）
                  if (!RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(normalized)) {
                    return 'Please enter a valid 16-character voucher code.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Verify 按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('scan_verify_btn'),
                  onPressed: (isLoading || _isVerifying) ? null : _verifyManual,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    disabledBackgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: (isLoading || _isVerifying)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// 手动输入：将 16 位字母数字格式化为 XXXX-XXXX-XXXX-XXXX
// =============================================================
class _CouponCodeDashInputFormatter extends TextInputFormatter {
  const _CouponCodeDashInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 只保留字母和数字，统一转大写
    final chars = newValue.text
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final limited = chars.length > 16 ? chars.substring(0, 16) : chars;

    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write('-');
      buffer.write(limited[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// =============================================================
// 扫码取景框遮罩组件
// =============================================================
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.isLoading});
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(isLoading: isLoading),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.isLoading});
  final bool isLoading;

  @override
  void paint(Canvas canvas, Size size) {
    const scanBoxSize = 260.0;
    const cornerRadius = 16.0;
    const cornerLen = 28.0;
    const strokeW = 3.5;

    final cx = size.width / 2;
    final cy = size.height / 2 - 40; // 略偏上，留出底部文字空间

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: scanBoxSize,
      height: scanBoxSize,
    );

    // 暗色遮罩（取景框外区域）
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(cornerRadius)));
    final clipPath =
        Path.combine(PathOperation.difference, fullPath, holePath);
    canvas.drawPath(clipPath, overlayPaint);

    // 四角边框
    final cornerPaint = Paint()
      ..color = isLoading ? Colors.orange : const Color(0xFFFF6B35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;

    // 左上角
    canvas.drawPath(
        Path()
          ..moveTo(l + cornerLen, t)
          ..lineTo(l + cornerRadius, t)
          ..arcToPoint(Offset(l, t + cornerRadius),
              radius: const Radius.circular(cornerRadius))
          ..lineTo(l, t + cornerLen),
        cornerPaint);
    // 右上角
    canvas.drawPath(
        Path()
          ..moveTo(r - cornerLen, t)
          ..lineTo(r - cornerRadius, t)
          ..arcToPoint(Offset(r, t + cornerRadius),
              radius: const Radius.circular(cornerRadius), clockwise: true)
          ..lineTo(r, t + cornerLen),
        cornerPaint);
    // 左下角
    canvas.drawPath(
        Path()
          ..moveTo(l, b - cornerLen)
          ..lineTo(l, b - cornerRadius)
          ..arcToPoint(Offset(l + cornerRadius, b),
              radius: const Radius.circular(cornerRadius), clockwise: true)
          ..lineTo(l + cornerLen, b),
        cornerPaint);
    // 右下角
    canvas.drawPath(
        Path()
          ..moveTo(r, b - cornerLen)
          ..lineTo(r, b - cornerRadius)
          ..arcToPoint(Offset(r - cornerRadius, b),
              radius: const Radius.circular(cornerRadius))
          ..lineTo(r - cornerLen, b),
        cornerPaint);
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) =>
      oldDelegate.isLoading != isLoading;
}

// =============================================================
// 手电筒按钮组件
// =============================================================
class _TorchButton extends StatefulWidget {
  const _TorchButton({required this.controller});
  final MobileScannerController? controller;

  @override
  State<_TorchButton> createState() => _TorchButtonState();
}

class _TorchButtonState extends State<_TorchButton> {
  bool _torchOn = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.controller?.toggleTorch();
        setState(() => _torchOn = !_torchOn);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _torchOn
              ? const Color(0xFFFF6B35)
              : Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
