import 'package:flutter/material.dart';

class AsyncPlaceholder extends StatelessWidget {
  const AsyncPlaceholder({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(label));
  }
}
