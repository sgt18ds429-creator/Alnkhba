import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/voice_assistant_state.dart';
import '../services/voice_command_parser.dart';
import '../providers/chat_provider.dart';
import 'api_service.dart';

class VoiceAssistantService extends ChangeNotifier {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService = ApiService();

  VoiceAssistantState _state = VoiceAssistantState.idle;
  VoiceAssistantState get state => _state;

  String _transcript = '';
  String get transcript => _transcript;

  String _statusLabel = 'أنا جاهز... قل "Hi Ray" أو انقر للمحادثة';
  String get statusLabel => _statusLabel;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _speechInitialized = false;
  Timer? _silenceTimer;
  bool _isPlayingChunkLoop = false;
  StreamSubscription<PlayerState>? _playerStateSub;

  ChatProvider? _lastChatProvider;

  VoiceAssistantService() {
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((pState) {
      if (_isPlayingChunkLoop) return;
      if (pState == PlayerState.completed || pState == PlayerState.stopped) {
        _onSpeakingCompleted();
      }
    });
  }

  void _setState(VoiceAssistantState newState, {String? label, String? error}) {
    _state = newState;
    if (label != null) _statusLabel = label;
    if (error != null) _errorMessage = error;
    notifyListeners();
  }

  void _onSpeakingCompleted() {
    if (_state == VoiceAssistantState.speaking) {
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... قل "Hi Ray" أو انقر للمحادثة');

      // Auto-resume mic in idle state to catch wake words without tapping
      if (_isModalOpen && _lastChatProvider != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_state == VoiceAssistantState.idle) {
            _startIdleListening();
          }
        });
      }
    }
  }

  Future<void> _startIdleListening() async {
    if (!_isModalOpen || _lastChatProvider == null) return;
    try {
      if (_speech.isListening) await _speech.stop();
      await _speech.listen(
        localeId: 'ar-SA',
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 10),
        cancelOnError: false,
        partialResults: true,
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty && _state == VoiceAssistantState.idle) {
            if (VoiceCommandParser.isWakeWord(words)) {
              _executeVoiceCommand(VoiceCommandType.wakeGreeting, _lastChatProvider!);
            }
          }
        },
      );
    } catch (_) {}
  }

  void _scheduleAutoProcess(ChatProvider chatProvider, {bool isFinal = false}) {
    _silenceTimer?.cancel();
    if (_state == VoiceAssistantState.listening) {
      _setState(VoiceAssistantState.detectingSilence, label: 'جارٍ اكتشاف السكوت...');
    }

    // Dynamic silence timer: 300ms if engine completed, 1200ms for short input, 2000ms max
    final durationMs = isFinal ? 300 : (_transcript.split(' ').length <= 4 ? 1200 : 2000);

    _silenceTimer = Timer(Duration(milliseconds: durationMs), () {
      if (_state == VoiceAssistantState.listening ||
          _state == VoiceAssistantState.detectingSilence) {
        _setState(VoiceAssistantState.processing, label: 'جارٍ معالجة الصوت والنص...');
        stopFallbackAndProcess(chatProvider);
      }
    });
  }

  bool _isModalOpen = false;

  void forceStopEverything() {
    _isModalOpen = false;
    _silenceTimer?.cancel();
    try {
      if (_speech.isListening) {
        _speech.cancel();
        // CRITICAL FIX: The speech_to_text plugin has a known bug on Android where cancel()
        // does not reliably reset its internal isListening flag. If we don't re-initialize,
        // the plugin becomes a zombie and ignores all future listen() calls silently!
        _speechInitialized = false; // Force re-initialization on next listen
      }
      _audioPlayer.stop();
    } catch (_) {}
    _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
  }

  Future<void> startListening(ChatProvider chatProvider) async {
    _isModalOpen = true;
    _lastChatProvider = chatProvider;
    _silenceTimer?.cancel();
    _setState(VoiceAssistantState.wake, label: 'تفعيل المساعد الصوتي...');
    await stopSpeaking();

    // Force stop any background DarkRoom / Wake Word service to release the mic lock!
    await chatProvider.forceStopVoiceServices();
    await Future.delayed(const Duration(milliseconds: 500));

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        _setState(VoiceAssistantState.error, label: 'حدث خطأ', error: 'إذن الميكروفون مرفوض.');
        return;
      }
    }

    _transcript = '';
    _errorMessage = null;

    _setState(VoiceAssistantState.startingRecognition, label: 'جارٍ بدء التعرف الصوتي...');
    try {
      if (!_speechInitialized) {
        _speechInitialized = await _speech.initialize(
          onError: (error) {
            debugPrint('[VoiceAssistantService] STT Error: ${error.errorMsg}');
            if (_state == VoiceAssistantState.listening ||
                _state == VoiceAssistantState.detectingSilence) {
              if (error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout') {
                if (_isModalOpen) {
                  // Retry listening silently on timeout
                  startListening(chatProvider);
                }
              } else {
                _setState(
                  VoiceAssistantState.error,
                  label: 'حدث خطأ بالمايكروفون',
                  error: error.errorMsg,
                );
              }
            }
          },
          onStatus: (status) {
            if (status == 'notListening' || status == 'done') {
              if (_state == VoiceAssistantState.listening ||
                  _state == VoiceAssistantState.detectingSilence) {
                if (_transcript.trim().isNotEmpty) {
                  _scheduleAutoProcess(chatProvider, isFinal: true);
                } else {
                  // Keep microphone active if transcript is empty
                  if (_isModalOpen) startListening(chatProvider);
                }
              } else if (_state == VoiceAssistantState.idle && _isModalOpen) {
                // Keep the microphone listening silently for wake words!
                _startIdleListening();
              }
            }
          },
        );
      }

      if (_speechInitialized) {
        _setState(VoiceAssistantState.listening, label: 'أنا أستمع... تحدث الآن');
        await _speech.listen(
          localeId: 'ar-SA',
          listenMode: stt.ListenMode.confirmation, // Faster, avoids freeze
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 10),
          cancelOnError: true, // Crucial: Fail fast so onError handles it
          partialResults: true,
          onResult: (result) {
            final words = result.recognizedWords.trim();
            if (words.isNotEmpty) {
              _transcript = words;
              notifyListeners();

              // Check for instant wake word recognition (0ms delay for pure wake word)
              final cleanedPrefix = VoiceCommandParser.cleanWakeWordPrefix(words);
              if (VoiceCommandParser.isWakeWord(words) && cleanedPrefix.isEmpty) {
                _silenceTimer?.cancel();
                _executeVoiceCommand(VoiceCommandType.wakeGreeting, chatProvider);
                return;
              }

              _scheduleAutoProcess(chatProvider, isFinal: result.finalResult);
            }
          },
        );
      } else {
        _setState(VoiceAssistantState.idle, label: 'فشل تهيئة المايكروفون');
      }
    } catch (_) {
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
    }
  }

  Future<void> stopFallbackAndProcess(ChatProvider chatProvider) async {
    _silenceTimer?.cancel();
    _setState(VoiceAssistantState.waitingGemini, label: 'انتظار الذكاء الاصطناعي...');

    try {
      if (_speech.isListening) {
        await _speech.cancel(); // Forcefully kill
        _speechInitialized = false; // Force re-initialization on next listen
      }
    } catch (_) {}

    if (_transcript.trim().isNotEmpty) {
      await processUserInput(_transcript, chatProvider);
      return;
    }

    _setState(VoiceAssistantState.idle, label: 'أنا جاهز... قل "Hi Ray" أو انقر للمحادثة');
  }

  Future<void> processUserInput(String input, ChatProvider chatProvider) async {
    String cleanInput = input.trim();
    if (cleanInput.isEmpty) {
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
      return;
    }

    // Strip wake word prefix if user asked "Hi Ray [Question]"
    final queryWithoutWake = VoiceCommandParser.cleanWakeWordPrefix(cleanInput);
    if (queryWithoutWake.isNotEmpty) {
      cleanInput = queryWithoutWake;
    }

    _setState(VoiceAssistantState.processing, label: 'أفكر...');
    final cmd = VoiceCommandParser.parseCommand(cleanInput);
    if (cmd != VoiceCommandType.none) {
      await _executeVoiceCommand(cmd, chatProvider);
      return;
    }
    await _sendQueryToAi(cleanInput, chatProvider);
  }

  Future<void> _executeVoiceCommand(VoiceCommandType cmd, ChatProvider chatProvider) async {
    switch (cmd) {
      case VoiceCommandType.wakeGreeting:
        _transcript = 'Hi Ray';
        _setState(VoiceAssistantState.listening, label: 'أهلاً بك! تفضل اسألني');
        startListening(chatProvider);
        break;
      case VoiceCommandType.thankYou:
        _setState(VoiceAssistantState.idle, label: 'في الخدمة دائماً');
        break;
      case VoiceCommandType.openChat:
        _setState(VoiceAssistantState.idle, label: 'تم فتح المحادثة');
        await speakText('تم فتح المحادثة');
        break;
      case VoiceCommandType.newChat:
        chatProvider.clearChat();
        _setState(VoiceAssistantState.idle, label: 'بدأت محادثة جديدة');
        await speakText('تم بدء محادثة جديدة');
        break;
      case VoiceCommandType.readLastResponse:
        if (chatProvider.messages.isNotEmpty) {
          final lastModel = chatProvider.messages.lastWhere(
            (m) => m.role == 'model',
            orElse: () => chatProvider.messages.last,
          );
          await speakText(lastModel.text);
        }
        break;
      case VoiceCommandType.stopSpeaking:
        await stopSpeaking();
        break;
      case VoiceCommandType.clearChat:
        chatProvider.clearChat();
        _setState(VoiceAssistantState.idle, label: 'تم مسح المحادثة');
        await speakText('تم مسح المحادثة');
        break;
      case VoiceCommandType.none:
        break;
    }
  }

  Future<void> _sendQueryToAi(String query, ChatProvider chatProvider) async {
    try {
      final initialCount = chatProvider.messages.length;
      await chatProvider.sendMessage(query);

      final newMessages = chatProvider.messages;
      if (newMessages.length > initialCount) {
        final lastMsg = newMessages.last;
        if (lastMsg.role == 'model' && lastMsg.text.isNotEmpty) {
          await speakText(lastMsg.text);
          return;
        }
      }
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
    } catch (_) {
      _setState(
        VoiceAssistantState.error,
        label: 'حدث خطأ',
        error: 'تعذر الاتصال بالذكاء الاصطناعي',
      );
    }
  }

  List<String> _splitTextIntoSafeChunks(String text) {
    final List<String> safeChunks = [];
    final sentences = text.split(RegExp(r'(?<=[.!?\n،,؛;])\s+'));
    for (final sentence in sentences) {
      final cleanSentence = sentence.trim();
      if (cleanSentence.isEmpty) continue;
      if (cleanSentence.length <= 150) {
        safeChunks.add(cleanSentence);
      } else {
        final words = cleanSentence.split(RegExp(r'\s+'));
        String currentSubChunk = '';
        for (final word in words) {
          if ('$currentSubChunk $word'.trim().length <= 150) {
            currentSubChunk = '$currentSubChunk $word'.trim();
          } else {
            if (currentSubChunk.isNotEmpty) safeChunks.add(currentSubChunk);
            currentSubChunk = word;
          }
        }
        if (currentSubChunk.isNotEmpty) safeChunks.add(currentSubChunk);
      }
    }
    return safeChunks;
  }

  Future<void> speakText(String text) async {
    await stopSpeaking();
    if (text.trim().isEmpty) return;

    _setState(VoiceAssistantState.speaking, label: 'أتحدث...');

    String cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    cleanText = cleanText.replaceAll(RegExp(r'https?://[^\s]+'), '').trim();
    cleanText = cleanText
        .replaceAll(RegExp(r'Eliteradiq.*', caseSensitive: false, dotAll: true), '')
        .trim();
    cleanText = cleanText.replaceAll(RegExp(r'[-*_]{2,}'), '');
    cleanText = cleanText.replaceAll(RegExp(r'#+'), '');
    cleanText = cleanText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('. ');
    cleanText = cleanText.replaceAll(RegExp(r'\.\s*\.'), '.').trim();

    if (cleanText.isEmpty) {
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
      return;
    }

    final chunks = _splitTextIntoSafeChunks(cleanText);
    if (chunks.isEmpty) {
      _onSpeakingCompleted();
      return;
    }

    _isPlayingChunkLoop = true;
    try {
      for (final chunk in chunks) {
        if (_state != VoiceAssistantState.speaking) {
          break;
        }
        final audioBytes = await _apiService.fetchTTS(chunk);
        if (audioBytes != null && audioBytes.isNotEmpty) {
          final completer = Completer<void>();
          late StreamSubscription sub;
          sub = _audioPlayer.onPlayerStateChanged.listen((state) {
            if (state == PlayerState.completed || state == PlayerState.stopped) {
              if (!completer.isCompleted) completer.complete();
            }
          });
          try {
            await _audioPlayer.setPlaybackRate(1.15);
            await _audioPlayer.play(BytesSource(Uint8List.fromList(audioBytes)));
            await completer.future.timeout(const Duration(seconds: 20));
          } catch (_) {
            if (!completer.isCompleted) completer.complete();
          } finally {
            await sub.cancel();
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
      }
    } finally {
      _isPlayingChunkLoop = false;
    }

    _onSpeakingCompleted();
  }

  Future<void> stopSpeaking() async {
    _silenceTimer?.cancel();
    _isPlayingChunkLoop = false;
    try {
      await _speech.cancel();
      await _audioPlayer.stop();
    } catch (_) {}
    if (_state == VoiceAssistantState.speaking) {
      _setState(VoiceAssistantState.idle, label: 'أنا جاهز... انقر للمحادثة');
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _playerStateSub?.cancel();
    try {
      _speech.cancel();
      _audioPlayer.dispose();
    } catch (_) {}
    _apiService.dispose();
    super.dispose();
  }
}
