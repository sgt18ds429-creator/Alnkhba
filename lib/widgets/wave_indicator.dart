import 'dart:math';
import 'package:flutter/material.dart';

class WaveIndicator extends StatefulWidget {
  final Color color;
  final int count;

  const WaveIndicator({
    super.key,
    this.color = const Color(0xFF22C55E), // Default green
    this.count = 5,
  });

  @override
  State<WaveIndicator> createState() => _WaveIndicatorState();
}

class _WaveIndicatorState extends State<WaveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heightMultipliers = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();

    final rand = Random();
    for (int i = 0; i < widget.count; i++) {
      _heightMultipliers.add(0.4 + rand.nextDouble() * 0.6);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(widget.count, (index) {
            // Create a sine wave phase shift for each bar to look like a fluid wave
            final value = sin((_controller.value * 2 * pi) + (index * 0.8));
            final heightFactor = (value + 1.0) / 2.0; // Normalized to 0.0 - 1.0

            final height = 4.0 + (heightFactor * 16.0 * _heightMultipliers[index]);

            return Container(
              width: 3.5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.5 + (heightFactor * 0.5)),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        );
      },
    );
  }
}
