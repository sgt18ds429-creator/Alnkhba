import 'dart:math' as math;
import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Calculate a staggered delay for each dot
            final offset = index * 0.2;
            final double t = (_controller.value - offset) % 1.0;

            // Pulse logic: scale up and down, and change opacity
            // We want it to pulse when t is between 0.0 and 0.5
            double scale = 1.0;
            double opacity = 0.3;

            if (t >= 0.0 && t <= 0.5) {
              // Sine wave for smooth pulsing
              final double curve = (t * 2) * math.pi; // 0 to pi
              final double sinVal = math.sin(curve);
              scale = 1.0 + (0.5 * sinVal);
              opacity = 0.3 + (0.7 * sinVal);
            } else if (t < 0.0) {
              // Handle negative wrap around (before offset)
              final tWrapped = t + 1.0;
              if (tWrapped >= 0.0 && tWrapped <= 0.5) {
                final double curve = (tWrapped * 2) * math.pi;
                final double sinVal = math.sin(curve);
                scale = 1.0 + (0.5 * sinVal);
                opacity = 0.3 + (0.7 * sinVal);
              }
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              width: 8 * scale,
              height: 8 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withOpacity(opacity),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF087CFF).withOpacity(opacity * 0.8),
                    blurRadius: 6 * scale,
                    spreadRadius: 2 * scale,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}
