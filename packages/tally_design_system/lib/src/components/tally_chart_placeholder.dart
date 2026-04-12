import 'package:flutter/material.dart';

class TallyChartPlaceholder extends StatelessWidget {
  const TallyChartPlaceholder({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
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
