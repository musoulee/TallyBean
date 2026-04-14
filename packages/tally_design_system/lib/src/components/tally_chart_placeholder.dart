import 'package:flutter/material.dart';

class TallyChartPlaceholder extends StatelessWidget {
  const TallyChartPlaceholder({
    super.key,
    required this.label,
    this.height = 96,
  });

  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFDCEED7), Color(0xFFF4FAF2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(child: Text(label)),
    );
  }
}
