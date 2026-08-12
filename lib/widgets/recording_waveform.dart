import 'dart:math';
import 'package:flutter/material.dart';

class RecordingWaveform extends StatefulWidget {
  final bool isRecording;
  final bool isPaused;
  final Color color;

  const RecordingWaveform({
    super.key,
    required this.isRecording,
    required this.isPaused,
    this.color = const Color(0xFFC5A059), // Babylonian Gold
  });

  @override
  State<RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<RecordingWaveform> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = List.generate(24, (_) => 5.0);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
      ..addListener(() {
        if (widget.isRecording && !widget.isPaused) {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              // Generate dynamic heights
              _barHeights[i] = 5.0 + _random.nextDouble() * 38.0;
            }
          });
        }
      });

    if (widget.isRecording && !widget.isPaused) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant RecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !widget.isPaused) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      setState(() {
        // Reset bars to resting flat line state
        _barHeights.fillRange(0, _barHeights.length, 5.0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _barHeights.map((height) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 4.0,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2.0),
            decoration: BoxDecoration(
              color: widget.isPaused
                  ? widget.color.withOpacity(0.4)
                  : widget.color.withOpacity(0.85),
              borderRadius: BorderRadius.circular(2.0),
            ),
          );
        }).toList(),
      ),
    );
  }
}
