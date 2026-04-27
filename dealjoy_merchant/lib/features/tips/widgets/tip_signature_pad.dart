// 小费电子签名区：导出 PNG base64 供 create-tip-payment-intent 上传

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class TipSignaturePad extends StatefulWidget {
  const TipSignaturePad({
    super.key,
    required this.onChanged,
  });

  final void Function(bool hasSignature) onChanged;

  @override
  TipSignaturePadState createState() => TipSignaturePadState();
}

class TipSignaturePadState extends State<TipSignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;
  final GlobalKey _boundaryKey = GlobalKey();

  /// 至少一笔含 2+ 采样点，避免仅误触单点
  bool get hasSignature => _strokes.any((s) => s.length >= 2);

  /// PNG 的 Base64（不含 data URL 前缀；Edge 与 raw 或 data URL 均兼容）
  Future<String> toPngBase64() async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null) {
      throw StateError('Signature pad not laid out');
    }
    final boundary = ctx.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('toByteData failed');
    }
    return base64Encode(data.buffer.asUint8List());
  }

  void clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = null;
    });
    widget.onChanged(false);
  }

  void _notify() {
    widget.onChanged(hasSignature);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade400, width: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) {
              setState(() {
                _currentStroke = [d.localPosition];
                _strokes.add(_currentStroke!);
              });
              _notify();
            },
            onPanUpdate: (d) {
              if (_currentStroke == null) return;
              setState(() {
                _currentStroke!.add(d.localPosition);
              });
              _notify();
            },
            onPanEnd: (_) {
              _currentStroke = null;
            },
            onPanCancel: () {
              _currentStroke = null;
            },
            child: CustomPaint(
              painter: _TipSignaturePainter(
                strokes: _strokes,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TipSignaturePainter extends CustomPainter {
  _TipSignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        final dot = Paint()
          ..color = const Color(0xFF1A1A1A)
          ..strokeWidth = 3
          ..style = PaintingStyle.fill;
        canvas.drawCircle(s.first, 1.2, dot);
        continue;
      }
      for (var i = 0; i < s.length - 1; i++) {
        canvas.drawLine(s[i], s[i + 1], linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TipSignaturePainter old) => true;
}
