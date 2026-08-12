import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/voice_assistant_state.dart';
import '../services/voice_assistant_service.dart';
import '../providers/chat_provider.dart';
import 'wave_indicator.dart';

class VoiceAssistantModal extends StatefulWidget {
  const VoiceAssistantModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceAssistantModal(),
    );
  }

  @override
  State<VoiceAssistantModal> createState() => _VoiceAssistantModalState();
}

class _VoiceAssistantModalState extends State<VoiceAssistantModal> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  ChatProvider? _chatProvider;
  VoiceAssistantService? _assistant;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.18,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // Auto start listening on modal presentation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final assistant = Provider.of<VoiceAssistantService>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      _assistant = assistant;
      _chatProvider = chatProvider;
      await assistant.startListening(chatProvider);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();

    // Stop the VoiceAssistantService's active/idle listening loop first
    try {
      _assistant?.forceStopEverything();
    } catch (error) {
      debugPrint('[VoiceAssistantModal] stop error: $error');
    }

    // Resume background listening (DarkRoom mode) when modal is dismissed.
    final chatProvider = _chatProvider;
    if (chatProvider != null) {
      unawaited(
        chatProvider.resumeVoiceServicesIfNeeded().catchError((Object error) {
          debugPrint('[VoiceAssistantModal] resume error: $error');
        }),
      );
    }

    super.dispose();
  }

  Color _getStateColor(VoiceAssistantState state) {
    switch (state) {
      case VoiceAssistantState.wake:
      case VoiceAssistantState.releasingAudio:
      case VoiceAssistantState.startingRecorder:
      case VoiceAssistantState.startingRecognition:
        return const Color(0xFF6366F1); // Indigo / Purple setup
      case VoiceAssistantState.listening:
        return const Color(0xFFF59E0B); // Amber / Gold listening
      case VoiceAssistantState.detectingSilence:
        return const Color(0xFF10B981); // Emerald Green silence detector
      case VoiceAssistantState.processing:
      case VoiceAssistantState.waitingGemini:
        return const Color(0xFF3B82F6); // Blue processing / thinking
      case VoiceAssistantState.speaking:
        return const Color(0xFF8B5CF6); // Purple TTS output
      case VoiceAssistantState.error:
        return const Color(0xFFEF4444); // Red error
      case VoiceAssistantState.idle:
      default:
        return const Color(0xFFC5A059); // Premium Gold
    }
  }

  IconData _getStateIcon(VoiceAssistantState state) {
    switch (state) {
      case VoiceAssistantState.wake:
      case VoiceAssistantState.releasingAudio:
        return Icons.power_settings_new;
      case VoiceAssistantState.startingRecorder:
        return Icons.graphic_eq;
      case VoiceAssistantState.startingRecognition:
        return Icons.hearing;
      case VoiceAssistantState.listening:
        return Icons.mic;
      case VoiceAssistantState.detectingSilence:
        return Icons.record_voice_over;
      case VoiceAssistantState.processing:
      case VoiceAssistantState.waitingGemini:
        return Icons.auto_awesome;
      case VoiceAssistantState.speaking:
        return Icons.volume_up;
      case VoiceAssistantState.error:
        return Icons.error_outline;
      case VoiceAssistantState.idle:
      default:
        return Icons.mic_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistant = Provider.of<VoiceAssistantService>(context);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final stateColor = _getStateColor(assistant.state);

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32.0)),
        border: Border.all(color: stateColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: stateColor.withOpacity(0.2), blurRadius: 30.0, spreadRadius: 2.0),
        ],
      ),
      child: Column(
        children: [
          // Drag handle indicator
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header title: "مساعد النخبة"
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome, color: stateColor, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                'Hi Ray / Hi Sono - مساعد النخبة الصوتي',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),

          const Spacer(),

          // Central Large Animated Siri/Bixby Mic Button
          GestureDetector(
            onTap: () {
              if (assistant.state == VoiceAssistantState.speaking) {
                // Barge-in: Stop speaking immediately and listen
                assistant.startListening(chatProvider);
              } else if (assistant.state == VoiceAssistantState.listening ||
                  assistant.state == VoiceAssistantState.detectingSilence) {
                // Stop listening and process
                assistant.stopFallbackAndProcess(chatProvider);
              } else {
                assistant.startListening(chatProvider);
              }
            },
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final scale =
                    (assistant.state == VoiceAssistantState.listening ||
                        assistant.state == VoiceAssistantState.detectingSilence ||
                        assistant.state == VoiceAssistantState.speaking)
                    ? _pulseAnimation.value
                    : 1.0;

                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 105,
                    height: 105,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: stateColor.withOpacity(0.15),
                      border: Border.all(color: stateColor, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: stateColor.withOpacity(0.4),
                          blurRadius: 24.0,
                          spreadRadius: 4.0,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: stateColor),
                        child: Icon(
                          _getStateIcon(assistant.state),
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Sound wave visualizer when listening / silence detecting / speaking
          if (assistant.state == VoiceAssistantState.listening ||
              assistant.state == VoiceAssistantState.detectingSilence ||
              assistant.state == VoiceAssistantState.speaking) ...[
            WaveIndicator(color: stateColor, count: 7),
            const SizedBox(height: 12),
          ],

          // Arabic Status Label ("أنا أستمع...", "أفكر...", "أتحدث...", "حدث خطأ")
          Text(
            assistant.statusLabel,
            style: TextStyle(
              color: stateColor,
              fontSize: 15.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
            textAlign: TextAlign.center,
          ),

          // Error / Transcript box
          if (assistant.errorMessage != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                assistant.errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12.0,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (assistant.transcript.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Text(
                '🗣 "${assistant.transcript}"',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12.5,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const Spacer(),

          // Quick Action Commands Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildQuickChip('شنو هو فحص الـ CT؟', assistant, chatProvider),
                const SizedBox(width: 8),
                _buildQuickChip('ابدأ محادثة جديدة', assistant, chatProvider),
                const SizedBox(width: 8),
                _buildQuickChip('اقرأ آخر إجابة', assistant, chatProvider),
                const SizedBox(width: 8),
                _buildQuickChip('أوقف الكلام', assistant, chatProvider),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String text, VoiceAssistantService assistant, ChatProvider provider) {
    return ActionChip(
      label: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11.5,
          fontFamily: 'Cairo',
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      onPressed: () {
        assistant.processUserInput(text, provider);
      },
    );
  }
}
