import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService;

  bool _speechEnabled = false;
  bool get isSpeechEnabled => _speechEnabled;
  stt.SpeechToText get speech => _speech;
  bool isListening = false;
  bool isSpeaking = false;

  // Callbacks
  Function()? onSpeechStart;
  Function()? onSpeechEnd;
  Function(String text)? onSpeechResult;
  Function(String text)? onPartialSpeechResult;
  Function(String error)? onSpeechError;
  Function()? onPlaybackComplete;
  Function(bool isSpeaking)? onSpeakingStatusChanged;

  StreamSubscription<PlayerState>? _playerStateSub;
  String _lastFinalText = '';
  bool _isCancelRequested = false;
  bool _isPlayingChunkLoop = false;

  VoiceService({ApiService? apiService}) : _apiService = apiService ?? ApiService() {
    // Microphone and speech-recognition permissions are requested only after
    // the user explicitly starts a voice feature.
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (_isPlayingChunkLoop) return;
      final oldSpeaking = isSpeaking;
      isSpeaking = state == PlayerState.playing;
      if (oldSpeaking != isSpeaking && onSpeakingStatusChanged != null) {
        onSpeakingStatusChanged!(isSpeaking);
      }
      if (state == PlayerState.completed) {
        if (onPlaybackComplete != null) {
          onPlaybackComplete!();
        }
      }
    });
  }

  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          _speechEnabled = false;
          if (onSpeechError != null) {
            onSpeechError!('إذن الميكروفون مرفوض');
          }
          return;
        }
      }

      _speechEnabled = await _speech.initialize(
        onStatus: (status) {
          if (status == 'listening') {
            isListening = true;
            if (onSpeechStart != null) onSpeechStart!();
          } else if (status == 'notListening' || status == 'done') {
            isListening = false;
            if (onSpeechEnd != null) onSpeechEnd!();
          }
        },
        onError: (SpeechRecognitionError error) {
          isListening = false;
          if (error.errorMsg == 'error_permission' || error.errorMsg == 'error_not_available') {
            _speechEnabled = false;
          }
          if (onSpeechError != null) onSpeechError!(error.errorMsg);
        },
      );
    } catch (_) {
      _speechEnabled = false;
    }
  }

  Future<void> reInitialize() async {
    await _initSpeech();
  }

  Future<void> startListeningForWakeWord() async {
    if (!_speechEnabled) return;
    _lastFinalText = '';

    void handleResult(SpeechRecognitionResult result) {
      if (result.finalResult && result.recognizedWords.isNotEmpty) {
        final text = result.recognizedWords.toLowerCase().trim();
        if (text != _lastFinalText && onSpeechResult != null) {
          _lastFinalText = text;
          onSpeechResult!(text);
        }
      } else {
        if (onPartialSpeechResult != null) {
          onPartialSpeechResult!(result.recognizedWords);
        }
      }
    }

    try {
      await _speech.listen(
        onResult: handleResult,
        localeId: 'ar-SA', // Use Arabic to catch "هاي راي" (accents ruin en_US)
        listenMode: stt.ListenMode.confirmation, // Optimized for short commands
        cancelOnError: true, // Fail fast on silence to restart cleanly
        partialResults: true,
      );
    } catch (_) {}
  }

  Future<void> startListening({String? localeId}) async {
    if (!_speechEnabled) {
      debugPrint(
        '[VoiceService] ⚠️ startListening called but _speechEnabled is false! Attempting to re-initialize...',
      );
      await _initSpeech();
      if (!_speechEnabled) {
        debugPrint('[VoiceService] ❌ Failed to self-heal. Microphone is dead.');
        return;
      }
    }

    _lastFinalText = '';

    void handleResult(SpeechRecognitionResult result) {
      if (result.finalResult && result.recognizedWords.isNotEmpty) {
        final text = result.recognizedWords.trim();
        if (text != _lastFinalText && onSpeechResult != null) {
          _lastFinalText = text;
          onSpeechResult!(text);
        }
      } else {
        if (onPartialSpeechResult != null) {
          onPartialSpeechResult!(result.recognizedWords);
        }
      }
    }

    try {
      await _speech.listen(
        onResult: handleResult,
        localeId: localeId ?? 'ar-SA',
        listenMode: stt.ListenMode.confirmation, // Faster and more reliable than dictation
        cancelOnError: true,
        partialResults: true,
      );
    } catch (e) {
      debugPrint('[VoiceService] ERROR in startListening: $e');
    }
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      try {
        await _speech
            .stop(); // Safe, graceful stop. cancel() causes permanent zombie state on Huawei.
      } catch (_) {}
    }
    isListening = false;
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

  Future<bool> speak(String text) async {
    await stopSpeaking();
    _isCancelRequested = false;

    String cleanText = text.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    cleanText = cleanText.replaceAll(RegExp(r'https?://[^\s]+'), '').trim();
    cleanText = cleanText
        .replaceAll(RegExp(r'Eliteradiq.*', caseSensitive: false, dotAll: true), '')
        .trim();
    cleanText = cleanText.replaceAll(RegExp(r'[-*_]{2,}'), '');
    cleanText = cleanText.replaceAll(RegExp(r'#+'), '');
    cleanText = cleanText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('. ');
    cleanText = cleanText.replaceAll(RegExp(r'\.\s*\.'), '.').trim();

    if (cleanText.isEmpty || _isCancelRequested) return false;

    isSpeaking = true;
    if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(true);

    final chunks = _splitTextIntoSafeChunks(cleanText);
    if (chunks.isEmpty) {
      isSpeaking = false;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(false);
      return false;
    }

    _isPlayingChunkLoop = true;
    int successCount = 0;
    try {
      for (final chunk in chunks) {
        if (!isSpeaking || _isCancelRequested) break;
        try {
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
              successCount++;
            } catch (_) {
              if (!completer.isCompleted) completer.complete();
            } finally {
              await sub.cancel();
            }
          } else {
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
        } catch (_) {}
      }
    } finally {
      final wasCancelled = _isCancelRequested;
      _isPlayingChunkLoop = false;
      isSpeaking = false;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(false);

      if (!wasCancelled && onPlaybackComplete != null) {
        // Fire playback complete ONLY if it finished naturally
        // If it was cancelled, stopSpeakingMessage() handles the restart manually.
        onPlaybackComplete!();
      }
    }

    return successCount > 0;
  }

  Future<void> playBase64Audio(String base64Audio) async {
    try {
      await stopSpeaking();
      final Uint8List bytes = base64Decode(base64Audio);
      isSpeaking = true;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(true);
      await _audioPlayer.setPlaybackRate(1.0); // Reset for base64 clips
      await _audioPlayer.play(BytesSource(bytes));
    } catch (_) {
      isSpeaking = false;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(false);
      if (onPlaybackComplete != null) onPlaybackComplete!();
    }
  }

  Future<void> playUrlAudio(String url) async {
    try {
      await stopSpeaking();
      isSpeaking = true;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(true);
      await _audioPlayer.setPlaybackRate(1.0); // Reset for url clips
      await _audioPlayer.play(UrlSource(url));
    } catch (_) {
      isSpeaking = false;
      if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(false);
      if (onPlaybackComplete != null) onPlaybackComplete!();
    }
  }

  Future<void> stopSpeaking() async {
    _isCancelRequested = true;
    _isPlayingChunkLoop = false;
    isSpeaking = false;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (onSpeakingStatusChanged != null) onSpeakingStatusChanged!(false);
  }

  void dispose() {
    _playerStateSub?.cancel();
    try {
      _speech.cancel();
    } catch (_) {}
    try {
      _audioPlayer.dispose();
    } catch (_) {}
    _apiService.dispose();
  }
}
