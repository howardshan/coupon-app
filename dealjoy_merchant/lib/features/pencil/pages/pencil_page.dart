import 'package:flutter/material.dart';

/// Pencil 占位页面
class PencilPage extends StatelessWidget {
  const PencilPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pencil')),
      body: const Center(
        child: Text(
          'Coming Soon',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }
}
