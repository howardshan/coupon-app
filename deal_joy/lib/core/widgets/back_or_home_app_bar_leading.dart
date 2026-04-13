import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// AppBar / SliverAppBar 用：有路由栈则 pop，否则回首页（避免 go 替换栈后无返回键）
Widget backOrHomeAppBarLeading(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    },
  );
}
