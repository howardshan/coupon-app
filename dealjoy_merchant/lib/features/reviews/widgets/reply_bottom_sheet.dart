// 商家回复输入 BottomSheet
// 功能:
//   - 多行文本输入框
//   - 实时字数统计（上限 300 字）
//   - Submit 按钮（提交中显示 loading，防重复点击）
//   - 提交成功后自动关闭

import 'package:flutter/material.dart';

class ReplyBottomSheet extends StatefulWidget {
  const ReplyBottomSheet({
    super.key,
    required this.onSubmit,
  });

  /// 提交回调，返回 true 表示提交成功（由调用方处理 API）
  /// 若抛出异常，BottomSheet 会显示错误提示
  final Future<void> Function(String reply) onSubmit;

  /// 弹出 BottomSheet 的便捷方法
  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(String reply) onSubmit,
  }) {
    return showModalBottomSheet(
      context:           context,
      isScrollControlled: true,   // 允许随键盘上推
      backgroundColor:   Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReplyBottomSheet(onSubmit: onSubmit),
    );
  }

  @override
  State<ReplyBottomSheet> createState() => _ReplyBottomSheetState();
}

class _ReplyBottomSheetState extends State<ReplyBottomSheet> {
  static const int _maxLength = 300;
  static const Color _primaryColor = Color(0xFFFF6B35);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // 剩余可输入字数
  int get _remaining => _maxLength - _controller.text.length;

  // 是否可提交（非空且未超限且未提交中）
  bool get _canSubmit =>
      _controller.text.trim().isNotEmpty &&
      _controller.text.length <= _maxLength &&
      !_isSubmitting;

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;

    setState(() {
      _isSubmitting   = true;
      _errorMessage   = null;
    });

    try {
      await widget.onSubmit(_controller.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst(RegExp(r'^.*?: '), '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 键盘高度偏移，避免遮挡输入框
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left:   20,
        right:  20,
        top:    20,
        bottom: bottomInset + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reply to Review',
                style: TextStyle(
                  fontSize:   18,
                  fontWeight: FontWeight.w600,
                  color:      Color(0xFF1A1A1A),
                ),
              ),
              // 关闭按钮
              IconButton(
                icon:    const Icon(Icons.close, color: Color(0xFF888888)),
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.of(context).pop(),
                padding:  EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 回复输入框
          Container(
            decoration: BoxDecoration(
              color:        const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _errorMessage != null
                    ? Colors.red.shade300
                    : const Color(0xFFE0E0E0),
              ),
            ),
            child: TextField(
              key: const ValueKey('reply_content_field'),
              controller:   _controller,
              focusNode:    _focusNode,
              maxLines:     5,
              minLines:     3,
              maxLength:    _maxLength,
              enabled:      !_isSubmitting,
              buildCounter: (_,
                  {required currentLength,
                  required isFocused,
                  required maxLength}) =>
                  null, // 隐藏默认计数器，改用自定义
              style: const TextStyle(
                fontSize: 15,
                color:    Color(0xFF1A1A1A),
              ),
              decoration: const InputDecoration(
                hintText:    'Write a professional reply to this review...',
                hintStyle:   TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                border:      InputBorder.none,
                contentPadding: EdgeInsets.all(14),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // 字数统计行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 错误提示
              if (_errorMessage != null)
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      color:    Colors.red.shade600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),

              // 剩余字数
              Text(
                '$_remaining / $_maxLength',
                style: TextStyle(
                  fontSize: 12,
                  color: _remaining < 0
                      ? Colors.red
                      : const Color(0xFF888888),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Submit 按钮
          SizedBox(
            height: 50,
            child: ElevatedButton(
              key: const ValueKey('reply_submit_btn'),
              onPressed: _canSubmit ? _handleSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:      _primaryColor,
                disabledBackgroundColor: const Color(0xFFCCCCCC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width:  22,
                      height: 22,
                      child:  CircularProgressIndicator(
                        color:       Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Submit Reply',
                      style: TextStyle(
                        fontSize:   16,
                        fontWeight: FontWeight.w600,
                        color:      Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
