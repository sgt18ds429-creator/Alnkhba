import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../services/voice_command_parser.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final VoiceService _voiceService = VoiceService();

  static const String _storageKey = 'nukhba_sessions_v3';
  static const String _userUidKey = 'eliteradiq_uid';

  List<ChatSession> sessions = [];
  String currentSessionId = '';
  List<Message> messages = [];
  List<HistoryItem> history = [];

  bool isLoading = false;
  bool isCallMode = false;
  bool darkroomMode = false;
  bool isDictating = false;
  String dictatedText = '';
  String voiceInputText = '';
  String wakeTranscript = '';
  String? error;

  List<AttachmentItem> selectedAttachments = [];
  String? prefilledText;
  StreamSubscription<String>? _activeStreamSubscription;
  Completer<void>? _activeSendCompleter;
  int _requestGeneration = 0;
  String? activeConsultantRoom;

  bool get activeRequestHasImage {
    for (final message in messages.reversed) {
      if (message.role == 'user') {
        return message.attachments?.any((item) => item.type == 'image') ?? false;
      }
    }
    return false;
  }

  void _completeActiveSend([Completer<void>? target]) {
    final completer = target ?? _activeSendCompleter;
    if (identical(_activeSendCompleter, completer)) {
      _activeSendCompleter = null;
    }
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  String userId = '';
  late final Future<void> _initialization;
  Future<void> _saveQueue = Future<void>.value();

  Timer? _speechSilenceTimer;
  String _finalCapturedText = '';
  bool _isTransitioningFromWakeWord = false;

  void _resetSilenceTimer() {
    _speechSilenceTimer?.cancel();
    _speechSilenceTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_finalCapturedText.isNotEmpty) {
        _sendCapturedVoiceQuestion();
      }
    });
  }

  bool _isPureWakeWord(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return true;
    final wakeRegex = RegExp(
      r'^(hi\s*ray|hi-ray|hiray|ray|هاي\s*راي|هاي\s*ري|يا\s*راي|هيري|هي\s*ري|hi\s*sono|hisono|هاي\s*سونو|هيسونو|هاي\s*صونو|هي\s*صونو|هصونو|حي\s*سونو|سونو|صونو|هاي\s*سانو|هيسانو|هاي\s*غي|هاي\s*غاي|هي\s*غي|hi\s*ghay|hi\s*ghi|highay|حي\s*غي|غي|غاي)\s*$',
      caseSensitive: false,
    );
    return wakeRegex.hasMatch(text);
  }

  void _sendCapturedVoiceQuestion() {
    _speechSilenceTimer?.cancel();
    final rawText = _finalCapturedText.trim().isNotEmpty
        ? _finalCapturedText.trim()
        : voiceInputText.trim();

    // Guard against empty or pure wake-word phrases
    if (rawText.isEmpty || _isPureWakeWord(rawText)) {
      _finalCapturedText = '';
      voiceInputText = '';
      dictatedText = '';
      return;
    }

    // Strip the wake word prefix before sending to Gemini
    final textToSend = VoiceCommandParser.cleanWakeWordPrefix(rawText);

    if (textToSend.isEmpty) {
      _finalCapturedText = '';
      voiceInputText = '';
      dictatedText = '';
      return;
    }

    if ((isCallMode || _handsFreeActive) && !isLoading && !_voiceService.isSpeaking) {
      _finalCapturedText = '';
      voiceInputText = '';
      dictatedText = '';

      if (darkroomMode && _handsFreeActive) {
        wakeTranscript = 'جاري إرسال سؤالك للذكاء الاصطناعي...';
      }

      _voiceService.stopListening();
      notifyListeners();
      sendMessage(textToSend);
    }
  }

  ChatProvider() {
    _initialization = _initProvider();

    // Bind VoiceService callbacks
    _voiceService.onSpeechStart = () {
      notifyListeners();
    };

    _voiceService.onSpeakingStatusChanged = (_) {
      notifyListeners();
    };

    _voiceService.onPlaybackComplete = _handlePlaybackComplete;

    _voiceService.onSpeechEnd = () {
      if (_isTransitioningFromWakeWord) return;
      notifyListeners();
      if (isDictating) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (isDictating && !_voiceService.isListening && !_voiceService.isSpeaking) {
            _voiceService.startListening();
          }
        });
        return;
      }

      // If final text was captured, send question cleanly
      if (_finalCapturedText.trim().isNotEmpty) {
        _sendCapturedVoiceQuestion();
        return;
      }

      // If no text captured yet, restart listening loop after a brief delay
      if (isCallMode || _handsFreeActive) {
        if (!_voiceService.isListening && !_voiceService.isSpeaking && !isLoading) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if ((isCallMode || (darkroomMode && _handsFreeActive)) &&
                !_voiceService.isListening &&
                !_voiceService.isSpeaking &&
                !isLoading) {
              _startListeningLoop();
            }
          });
        }
      } else if (darkroomMode &&
          !_handsFreeActive &&
          !_voiceService.isListening &&
          !_voiceService.isSpeaking &&
          !isLoading) {
        // STT session ended (timeout/done) in DarkRoom wake-word mode → restart wake word standby automatically
        Future.delayed(const Duration(milliseconds: 400), () {
          if (darkroomMode &&
              !_handsFreeActive &&
              !_voiceService.isListening &&
              !_voiceService.isSpeaking &&
              !isLoading) {
            debugPrint('[ChatProvider] 🔁 DarkRoom onSpeechEnd: restarting wake word standby...');
            _isStartingWakeWord = false; // Reset guard to allow restart
            _startWakeWordStandby();
          }
        });
      }
    };

    _voiceService.onPartialSpeechResult = (text) {
      if (text.trim().isEmpty) return;
      if (voiceInputText == text) return; // Avoid unnecessary rebuild if text has not changed
      if (isDictating) {
        dictatedText = text;
        notifyListeners();
        return;
      }
      if (darkroomMode && !_handsFreeActive) {
        _handleWakeWordDetection(text);
        return;
      }
      voiceInputText = text;
      dictatedText = text;

      // CRITICAL FIX: Show live user speech on the DarkRoom overlay!
      if (darkroomMode && _handsFreeActive) {
        wakeTranscript = text;
      }

      notifyListeners();
      if (isCallMode || _handsFreeActive) {
        _resetSilenceTimer();
      }
    };

    _voiceService.onSpeechResult = (text) {
      if (text.trim().isEmpty) return;
      if (isDictating) {
        dictatedText = text;
        notifyListeners();
        return;
      }
      if (darkroomMode && !_handsFreeActive) {
        _handleWakeWordDetection(text);
        return;
      }
      // Check for greeting / cancellation phrases in active loops
      final cleaned = text.trim().toLowerCase();
      if (cleaned.contains('شكرا') ||
          cleaned.contains('شكراً') ||
          cleaned.contains('شكرًا') ||
          cleaned.contains('توقف') ||
          cleaned.contains('إلغاء')) {
        _speechSilenceTimer?.cancel();
        _voiceService.stopListening();
        _voiceService.stopSpeaking();
        _finalCapturedText = '';
        voiceInputText = '';
        dictatedText = '';

        isCallMode = false;
        _handsFreeActive = false;
        darkroomMode = false;
        notifyListeners();

        // Save darkroom standby disabled state in memory
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool(_darkroomModeKey, false);
        });

        _playLocalPhrase('تدلل أستاذ');
        return;
      }

      _finalCapturedText = text.trim();
      voiceInputText = text.trim();
      dictatedText = text.trim();
      _sendCapturedVoiceQuestion();
    };

    _voiceService.onSpeechError = (err) async {
      if (_isTransitioningFromWakeWord) return;
      notifyListeners();

      final bool isFatalError =
          err.contains('مرفوض') ||
          err.contains('إذن') ||
          err.contains('غير متاحة') ||
          err.contains('صلاحية') ||
          err.contains('permission') ||
          err.contains('not available') ||
          err.contains('denied');

      if (isFatalError) {
        error = err;
        isCallMode = false;
        darkroomMode = false;
        _handsFreeActive = false;
        isDictating = false;
        notifyListeners();
        return;
      }

      if (_finalCapturedText.trim().isNotEmpty &&
          (isCallMode || _handsFreeActive) &&
          !isLoading &&
          !_voiceService.isSpeaking) {
        _sendCapturedVoiceQuestion();
        return;
      }

      // Restart loop if active — always reset guard flags to prevent deadlock
      if ((isCallMode || (darkroomMode && _handsFreeActive)) &&
          !isLoading &&
          !_voiceService.isSpeaking) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _isStartingListening = false; // Reset guard
          _startListeningLoop();
        });
      } else if (darkroomMode && !_handsFreeActive && !_voiceService.isSpeaking) {
        // Always restart wake word listening after any non-fatal STT error in DarkRoom mode
        int delayMs = 800;
        if (err == 'error_client' || err == 'error_busy') {
          delayMs = 2500; // Android needs more time to release the mic hardware lock
        }

        Future.delayed(Duration(milliseconds: delayMs), () {
          debugPrint(
            '[ChatProvider] 🔁 DarkRoom onSpeechError: restarting wake word standby after error... ($err)',
          );
          _isStartingWakeWord = false; // Reset guard to allow restart
          _startWakeWordStandby();
        });
      }
    };
  }

  String? currentlySpeakingMessageId;
  DateTime _lastStreamNotify = DateTime(0);

  /// Speak a specific message text (toggle: tap once to play, tap again to stop)
  Future<void> speakMessageText(String messageId, String text) async {
    // If already speaking THIS message → stop it
    if (currentlySpeakingMessageId == messageId) {
      await stopSpeakingMessage();
      return;
    }
    // speak() يتولى إيقاف أي صوت سابق بداخله بأمان
    await _voiceService.stopListening(); // CRITICAL: Stop STT so it doesn't hear the TTS and crash!

    currentlySpeakingMessageId = messageId;
    notifyListeners();
    final completed = await _voiceService.speak(text);
    currentlySpeakingMessageId = null;
    notifyListeners();

    // Always delegate to the unified handler to restore the appropriate listening loop (Active or Wake Word)
    if (completed) {
      _handlePlaybackComplete();
    }
  }

  Future<void> stopSpeakingMessage() async {
    currentlySpeakingMessageId = null;
    await _voiceService.stopSpeaking();
    notifyListeners();

    _handlePlaybackComplete();
  }

  bool get isListening => _voiceService.isListening;
  bool get isSpeaking => _voiceService.isSpeaking;

  // Track if user is in an active hands-free loop after wake word trigger
  bool _handsFreeActive = false;
  bool get isHandsFreeActive => _handsFreeActive;
  bool _isStartingListening = false;
  bool _isStartingWakeWord = false;
  static const String _darkroomModeKey = 'darkroom_mode_active';

  /// Production API endpoint. It is intentionally immutable at runtime.
  String get baseUrl => _apiService.baseUrl;

  Future<void> ensureInitialized() => _initialization;

  /// Load sessions, configurations, and user ID
  Future<void> _initProvider() async {
    final prefs = await SharedPreferences.getInstance();

    // User ID
    userId = prefs.getString(_userUidKey) ?? '';
    if (userId.isEmpty) {
      userId = _generateUuid();
      await prefs.setString(_userUidKey, userId);
    }

    // Load saved chats
    final String? sessionsRaw = prefs.getString(_storageKey);
    if (sessionsRaw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(sessionsRaw);
        sessions = decoded.map((s) => ChatSession.fromJson(s as Map<String, dynamic>)).toList();
      } catch (_) {
        sessions = [];
      }
    }

    // Never reopen the microphone merely because the app was restarted.
    // Voice standby always requires a fresh, explicit action in this session.
    if (prefs.getBool(_darkroomModeKey) == true) {
      await prefs.setBool(_darkroomModeKey, false);
    }
    darkroomMode = false;

    currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    notifyListeners();
  }

  /// Generate a simple UUID
  String _generateUuid() {
    final rand = Random.secure();
    return List.generate(32, (i) {
      if (i == 8 || i == 12 || i == 16 || i == 20) return '-';
      final n = rand.nextInt(16);
      return n.toRadixString(16);
    }).join();
  }

  /// Save sessions list locally
  Future<void> _saveSessionsToPrefs() {
    // Keep last 25 sessions in memory and on disk, and slim down messages
    // (remove base64 buffers) before persistence.
    if (sessions.length > 25) {
      sessions = sessions.take(25).toList();
    }
    final savedSessions = sessions.map((s) => s.toSlim().toJson()).toList();
    final encodedSnapshot = jsonEncode(savedSessions);
    _saveQueue = _saveQueue
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_storageKey, encodedSnapshot);
        })
        .catchError((Object error) {
          debugPrint('[ChatProvider] Failed to persist chat history: $error');
        });
    return _saveQueue;
  }

  /// Clear Attachments
  void clearAttachments() {
    selectedAttachments.clear();
    notifyListeners();
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < selectedAttachments.length) {
      selectedAttachments.removeAt(index);
      notifyListeners();
    }
  }

  static const int _maxAttachmentBytes = 12 * 1024 * 1024;

  int _attachmentSize(AttachmentItem item) {
    if (item.bytes != null) return item.bytes!.length;
    if (item.base64.startsWith('__')) return 0;
    return (item.base64.length * 3) ~/ 4;
  }

  void addAttachment(AttachmentItem item) {
    final size = _attachmentSize(item);
    if (size > _maxAttachmentBytes) {
      error = 'حجم الملف كبير جداً. الحد الأقصى 12 MB.';
      notifyListeners();
      return;
    }
    final withoutSameType = selectedAttachments
        .where((attachment) => attachment.type != item.type)
        .toList();
    final totalSize =
        withoutSameType.fold<int>(0, (sum, attachment) => sum + _attachmentSize(attachment)) + size;
    if (totalSize > _maxAttachmentBytes) {
      error = 'مجموع المرفقات أكبر من 12 MB. احذف مرفقاً ثم حاول مجدداً.';
      notifyListeners();
      return;
    }
    // The current backend accepts one image, one PDF and one audio recording.
    // Replacing the same type prevents the UI from implying that ignored files
    // will be analysed.
    selectedAttachments
      ..removeWhere((attachment) => attachment.type == item.type)
      ..add(item);
    error = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void consumePrefilledText() {
    prefilledText = null;
    notifyListeners();
  }

  void setPrefilledText(String text) {
    prefilledText = text;
    notifyListeners();
  }

  /// Select Attachment Info
  void selectImage(String base64, String mime, String name, {Uint8List? bytes}) {
    if (bytes != null && bytes.length > _maxAttachmentBytes) {
      error = 'حجم الصورة كبير جداً. الحد الأقصى 12 MB.';
      notifyListeners();
      return;
    }
    addAttachment(
      AttachmentItem(base64: base64, mime: mime, name: name, type: 'image', bytes: bytes),
    );
  }

  void selectPdf(String base64, String name, {Uint8List? bytes}) {
    if (bytes != null && bytes.length > _maxAttachmentBytes) {
      error = 'حجم ملف PDF كبير جداً. الحد الأقصى 12 MB.';
      notifyListeners();
      return;
    }
    final item = AttachmentItem(
      base64: base64,
      mime: 'application/pdf',
      name: name,
      type: 'pdf',
      bytes: bytes,
    );
    addAttachment(item);
  }

  /// Start Chat Session
  void clearChat() {
    _requestGeneration++;
    _voiceService.stopSpeaking();
    _voiceService.stopListening();
    if (_activeStreamSubscription != null) {
      _activeStreamSubscription!.cancel();
      _activeStreamSubscription = null;
    }
    _completeActiveSend();

    isCallMode = false;
    _handsFreeActive = false;
    currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    messages = [];
    history = [];
    error = null;
    clearAttachments();
    notifyListeners();
  }

  /// Removes every locally persisted conversation and voice-mode preference.
  /// A fresh anonymous identifier is created so a future activation cannot be
  /// correlated with the deleted local profile.
  Future<void> deleteAllLocalData() async {
    _requestGeneration++;
    _speechSilenceTimer?.cancel();
    await _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;
    _completeActiveSend();
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    sessions = [];
    messages = [];
    history = [];
    selectedAttachments = [];
    activeConsultantRoom = null;
    currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    isLoading = false;
    isCallMode = false;
    darkroomMode = false;
    _handsFreeActive = false;
    error = null;
    userId = _generateUuid();

    await _saveQueue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_darkroomModeKey);
    await prefs.remove('eliteradiq_safety_consent_2026_08');
    await prefs.setString(_userUidKey, userId);
    notifyListeners();
  }

  /// Load Session from History
  void loadSession(ChatSession session) {
    _requestGeneration++;
    _voiceService.stopSpeaking();
    _voiceService.stopListening();
    _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;
    _completeActiveSend();

    isCallMode = false;
    isLoading = false;
    _handsFreeActive = false;
    currentSessionId = session.id;
    messages = List.from(session.messages);
    history = List.from(session.history);
    error = null;
    clearAttachments();
    notifyListeners();
  }

  /// Delete Session from History
  void deleteSession(String id) {
    final wasCurrentSession = currentSessionId == id;
    sessions.removeWhere((s) => s.id == id);
    if (wasCurrentSession) {
      clearChat();
    }
    _saveSessionsToPrefs();
    notifyListeners();
  }

  /// Stop active text generation stream and TTS speaking
  void stopGenerating() {
    _requestGeneration++;
    if (_activeStreamSubscription != null) {
      _activeStreamSubscription!.cancel();
      _activeStreamSubscription = null;
    }
    _completeActiveSend();
    _voiceService.stopSpeaking();
    isLoading = false;

    // Save session state with current partial messages
    if (messages.isNotEmpty) {
      final sessionIndex = sessions.indexWhere((s) => s.id == currentSessionId);
      final currentSession = ChatSession(
        id: currentSessionId,
        title: messages.first.text.isNotEmpty ? messages.first.text : 'محادثة مصورة',
        createdAt: int.tryParse(currentSessionId) ?? DateTime.now().millisecondsSinceEpoch,
        messages: List.from(messages),
        history: List.from(history),
      );

      if (sessionIndex >= 0) {
        sessions[sessionIndex] = currentSession;
      } else {
        sessions.insert(0, currentSession);
      }
      _saveSessionsToPrefs();
    }

    notifyListeners();
  }

  /// Send Message (handles API, vision, text generation streaming, local TTS audio, image generation)
  Future<void> sendMessage(String text, {bool autoSpeak = false}) async {
    await _initialization;
    final trimmed = text.trim();

    if (trimmed.isEmpty && selectedAttachments.isEmpty) return;
    if (isLoading) return;

    error = null;
    isLoading = true;
    final requestGeneration = ++_requestGeneration;
    final sendCompleter = Completer<void>();
    _activeSendCompleter = sendCompleter;
    notifyListeners();

    // Copy attachments list for this message
    final List<AttachmentItem> messageAttachments = List.from(selectedAttachments);

    // Create User Message
    final userMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      text: trimmed,
      attachments: messageAttachments,
    );

    messages.add(userMsg);
    clearAttachments();
    notifyListeners();

    // Create placeholder Model Message for streaming
    final modelMsgId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final modelMsg = Message(id: modelMsgId, role: 'model', text: '');
    messages.add(modelMsg);
    notifyListeners();

    String accumulatedText = '';

    final stream = _apiService.sendChatStream(
      message: trimmed,
      history: history,
      userId: userId,
      attachments: messageAttachments,
      consultantRoom: activeConsultantRoom,
    );

    _activeStreamSubscription = stream.listen(
      (chunk) {
        accumulatedText += chunk;

        // Strip metadata tags so they aren't visible while typing
        String cleanedText = accumulatedText.replaceAll(RegExp(r'\[.*?\]'), '').trim();
        cleanedText = cleanedText
            .replaceAll(RegExp(r'Eliteradiq.*', caseSensitive: false, dotAll: true), '')
            .trim();

        final idx = messages.indexWhere((m) => m.id == modelMsgId);
        if (idx >= 0) {
          messages[idx] = messages[idx].copyWith(text: cleanedText);
          // Throttle UI updates to ~30fps for smooth word-by-word streaming
          final now = DateTime.now();
          if (now.difference(_lastStreamNotify).inMilliseconds >= 33) {
            _lastStreamNotify = now;
            notifyListeners();
          }
        }
      },
      onDone: () async {
        if (requestGeneration != _requestGeneration) return;
        _activeStreamSubscription = null;

        // Stream completed! Let's parse metadata from final accumulated text
        final parsed = _apiService.parseResponseMetadata(accumulatedText);
        final String replyText = parsed['reply'] ?? '';
        final String? generatedImagePrompt = parsed['generateImagePrompt'];
        final String? wikiImageTerm = parsed['wikiImageQuery'];
        final bool isPosQuery = parsed['isPositioningQuery'] ?? false;
        final String? youtubeQuery = parsed['youtubeQuery'];
        final bool? quizMode = parsed['quizMode'];

        String? wikiImageUrl;
        if (wikiImageTerm != null) {
          wikiImageUrl = await _apiService.fetchWikiImage(wikiImageTerm, isPositioning: isPosQuery);
          if (requestGeneration != _requestGeneration) return;
        }

        Map<String, String>? generatedImage;
        if (generatedImagePrompt != null && generatedImagePrompt.isNotEmpty) {
          generatedImage = await _apiService.fetchGeneratedImage(generatedImagePrompt);
          if (requestGeneration != _requestGeneration) return;
        }

        // Update Model Message with finalized metadata
        final finalizedMsg = Message(
          id: modelMsgId,
          role: 'model',
          text: replyText,
          generatedImage: generatedImage?['base64'],
          generatedImageMime: generatedImage?['mime'],
          wikiImageUrl: wikiImageUrl,
          quizMode: quizMode,
          youtubeQuery: youtubeQuery,
        );

        final idx = messages.indexWhere((m) => m.id == modelMsgId);
        if (idx >= 0) {
          messages[idx] = finalizedMsg;
        }

        history.add(
          HistoryItem(
            role: 'user',
            parts: [HistoryPart(text: trimmed.isNotEmpty ? trimmed : '[مرفق]')],
          ),
        );
        history.add(
          HistoryItem(
            role: 'model',
            parts: [HistoryPart(text: replyText)],
          ),
        );
        if (history.length > 40) {
          history = history.sublist(history.length - 40);
        }

        // Update/save sessions
        final sessionIndex = sessions.indexWhere((s) => s.id == currentSessionId);
        final currentSession = ChatSession(
          id: currentSessionId,
          title: messages.first.text.isNotEmpty ? messages.first.text : 'محادثة مصورة',
          createdAt: int.tryParse(currentSessionId) ?? DateTime.now().millisecondsSinceEpoch,
          messages: List.from(messages),
          history: List.from(history),
        );

        if (sessionIndex >= 0) {
          sessions[sessionIndex] = currentSession;
        } else {
          sessions.insert(0, currentSession);
        }
        _saveSessionsToPrefs();
        isLoading = false;
        notifyListeners();
        _completeActiveSend(sendCompleter);

        // Auto-play TTS if autoSpeak is requested OR continuous call/hands-free voice mode is active.
        // NOTE: لا نستدعي _handlePlaybackComplete() مباشرة هنا لأن VoiceService.onPlaybackComplete
        // مُعيَّن على _handlePlaybackComplete في المُنشئ. الاستدعاء المباشر يُسبب تكراراً.
        // نُعيد تشغيل الحلقة فقط في حالات الخطأ أو النص الفارغ حيث لا يوجد صوت.
        if (replyText.isNotEmpty &&
            (autoSpeak || isCallMode || (darkroomMode && _handsFreeActive))) {
          try {
            if (darkroomMode && _handsFreeActive) {
              wakeTranscript = 'المساعد يتحدث...';
              notifyListeners();
            }
            await _voiceService.speak(replyText);
            // انتهاء الصوت يُعالَج عبر onPlaybackComplete callback أو onSpeechEnd
          } catch (e) {
            debugPrint('[ChatProvider] TTS speak exception: $e');
            // عند الخطأ نُعيد تشغيل الحلقة يدوياً لأن الـ callback لن يُطلَق
            if (isCallMode || (darkroomMode && _handsFreeActive)) {
              _handlePlaybackComplete();
            }
          }
        } else if (replyText.isEmpty && (isCallMode || (darkroomMode && _handsFreeActive))) {
          // نص فارغ: لا يوجد صوت سيُشغَّل، نُعيد الحلقة مباشرة
          _handlePlaybackComplete();
        }
      },
      onError: (e) {
        if (requestGeneration != _requestGeneration) return;
        _activeStreamSubscription = null;
        isLoading = false;
        error = e.toString().replaceAll('Exception:', '');

        if (darkroomMode && _handsFreeActive) {
          wakeTranscript = 'حدث خطأ في الاتصال، جاري إعادة المحاولة...';
        }

        // Clean placeholder message if error occurred before any text was received
        final idx = messages.indexWhere((m) => m.id == modelMsgId);
        if (idx >= 0 && messages[idx].text.isEmpty) {
          messages.removeAt(idx);
        }
        notifyListeners();
        _completeActiveSend(sendCompleter);

        // Resume loop in case of errors
        if (isCallMode || (darkroomMode && _handsFreeActive)) {
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (darkroomMode && _handsFreeActive) {
              wakeTranscript = 'أنا أستمع...';
              notifyListeners();
            }
            _startListeningLoop();
          });
        }
      },
    );
    await sendCompleter.future;
  }

  Future<String?> reportMessage({
    required String messageId,
    required String messageText,
    required String reason,
  }) async {
    await _initialization;
    try {
      await _apiService.reportMessage(
        messageId: messageId,
        messageText: messageText,
        reason: reason,
        userId: userId,
      );
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception:', '').trim();
    }
  }

  /// Specialized academic room selection logic.
  void selectConsultantRoom(String roomName) {
    if (isLoading || _activeStreamSubscription != null) stopGenerating();
    activeConsultantRoom = roomName;
    messages = [];
    history = [];
    error = null;
    clearAttachments();
    currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    String welcomeMsg = '';
    switch (roomName) {
      case 'غرفة الأشعة التقليدية':
        welcomeMsg =
            'مرحباً بك في غرفة الأشعة التقليدية التعليمية. اسأل عن فحوصات أو وضعيات X-ray، وتحقق من القيم النهائية وفق بروتوكول مؤسستك.';
        break;
      case 'غرفة المفراس الحلزوني':
        welcomeMsg =
            'مرحباً بك في غرفة المفراس الحلزوني التعليمية (CT). تفضل بسؤالك عن تقنيات التصوير أو المقاطع التشريحية.';
        break;
      case 'غرفة الرنين المغناطيسي':
        welcomeMsg =
            'مرحباً بك في غرفة الرنين المغناطيسي التعليمية (MRI). اسأل عن البروتوكولات أو الفيزياء أو السلامة، مع اعتماد تعليمات موقع العمل.';
        break;
      case 'غرفة هشاشة العظام':
        welcomeMsg =
            'مرحباً بك في غرفة هشاشة العظام التعليمية (DEXA). اسأل عن فحوصات كثافة العظام وتفسيرها الأكاديمي.';
        break;
      case 'غرفة أشعة الثدي':
        welcomeMsg =
            'مرحباً بك في غرفة أشعة الثدي التعليمية (Mammography). تفضل باستفسارك عن الوضعيات أو مبادئ BI-RADS التعليمية.';
        break;
      case 'غرفة أشعة الأسنان':
        welcomeMsg =
            'مرحباً بك في غرفة أشعة الأسنان التعليمية. تفضل بسؤالك عن الأشعة البانورامية أو CBCT.';
        break;
      default:
        welcomeMsg =
            'مرحباً بك في الغرفة الأكاديمية المتخصصة. كيف يمكنني مساعدتك في الدراسة اليوم؟';
    }

    final modelMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'model',
      text: welcomeMsg,
    );
    messages.add(modelMsg);
    history.add(
      HistoryItem(
        role: 'model',
        parts: [HistoryPart(text: welcomeMsg)],
      ),
    );
    _saveSessionsToPrefs();
    notifyListeners();
  }

  void clearConsultantRoom() {
    activeConsultantRoom = null;
    notifyListeners();
  }

  ApiService get apiService => _apiService;

  void injectCustomMessages(Message userMsg, Message modelMsg) {
    messages.add(userMsg);
    messages.add(modelMsg);

    // Add to history
    history.add(
      HistoryItem(
        role: 'user',
        parts: [HistoryPart(text: userMsg.text.isNotEmpty ? userMsg.text : '[صورة الرؤية الحية]')],
      ),
    );
    history.add(
      HistoryItem(
        role: 'model',
        parts: [HistoryPart(text: modelMsg.text)],
      ),
    );

    // Update/save sessions
    final sessionIndex = sessions.indexWhere((s) => s.id == currentSessionId);
    final currentSession = ChatSession(
      id: currentSessionId,
      title: messages.first.text.isNotEmpty ? messages.first.text : 'مرئية حية',
      createdAt: int.tryParse(currentSessionId) ?? DateTime.now().millisecondsSinceEpoch,
      messages: List.from(messages),
      history: List.from(history),
    );

    if (sessionIndex >= 0) {
      sessions[sessionIndex] = currentSession;
    } else {
      sessions.insert(0, currentSession);
    }
    _saveSessionsToPrefs();
    notifyListeners();
  }

  Future<void> startDictation() async {
    await _voiceService.stopSpeaking();
    await _voiceService.stopListening();
    isCallMode = false;
    darkroomMode = false;
    _handsFreeActive = false;
    isDictating = true;
    dictatedText = '';
    error = null;
    notifyListeners();

    if (isDictating) {
      await _voiceService.startListening();
    }
  }

  Future<void> stopDictation() async {
    isDictating = false;
    await _voiceService.stopListening();
    notifyListeners();
  }

  void clearDictatedText() {
    dictatedText = '';
  }

  /// play pronunciation audio snippet
  Future<void> playAudioBase64(String base64) async {
    await _voiceService.playBase64Audio(base64);
  }

  /* ── Voice Modes: Manual Call & Darkroom (Wake Word) ── */

  /// Unified completion handler for TTS & Audio Player playback
  void _handlePlaybackComplete() {
    debugPrint('[ChatProvider] Playback complete -> Handling unified voice loop re-arm');
    currentlySpeakingMessageId = null;
    notifyListeners();

    if (!isAppInForeground) return;
    if (isLoading || _voiceService.isSpeaking || _voiceService.isListening) return;

    if (isCallMode || (darkroomMode && _handsFreeActive)) {
      // 1200ms delay is CRITICAL to allow speaker hardware buffer and room echo to fully dissipate before the mic opens.
      // Otherwise, the assistant will hear its own voice and answer itself!
      Future.delayed(const Duration(milliseconds: 1200), () {
        if ((isCallMode || (darkroomMode && _handsFreeActive)) &&
            !isLoading &&
            !_voiceService.isSpeaking &&
            !_voiceService.isListening) {
          if (darkroomMode && _handsFreeActive) {
            wakeTranscript = 'أنا أستمع...';
            notifyListeners();
          }
          _startListeningLoop();
        }
      });
    } else if (darkroomMode && !_handsFreeActive) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (darkroomMode &&
            !_handsFreeActive &&
            !isLoading &&
            !_voiceService.isSpeaking &&
            !_voiceService.isListening) {
          _startWakeWordStandby();
        }
      });
    }
  }

  /// Start Continuous Call Mode (Reads last AI answer if available, then auto-listens for next question)
  Future<void> startCall() async {
    // If already in call mode and speaking -> stop call/speech
    if (isCallMode && _voiceService.isSpeaking) {
      hangUp();
      return;
    }

    // Manual call mode owns the microphone exclusively and does not leave a
    // hidden wake-word listener armed after the call ends.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkroomModeKey, false);
    darkroomMode = false;
    isDictating = false;
    await _voiceService.stopListening();
    isCallMode = true;
    _handsFreeActive = false;
    error = null;
    notifyListeners();

    // If there is a last AI response, speak it out loud cleanly!
    final lastAiMsg = messages.lastWhere(
      (m) => m.role == 'model' && m.text.trim().isNotEmpty,
      orElse: () => Message(id: '', role: '', text: ''),
    );

    if (lastAiMsg.id.isNotEmpty && !_voiceService.isSpeaking) {
      try {
        currentlySpeakingMessageId = lastAiMsg.id;
        notifyListeners();
        final completed = await _voiceService.speak(lastAiMsg.text);
        currentlySpeakingMessageId = null;
        notifyListeners();
        // Only auto-listen for next question if speech completed normally (not cancelled)
        if (completed && isCallMode && !isLoading) {
          await Future.delayed(const Duration(milliseconds: 300));
          _startListeningLoop();
        }
      } catch (e) {
        debugPrint('[ChatProvider] startCall TTS error: $e');
        currentlySpeakingMessageId = null;
        _startListeningLoop();
      }
    } else {
      _startListeningLoop();
    }
  }

  /// Hang up Manual Call / Exit Continuous Voice Loops
  void hangUp() {
    _requestGeneration++;
    _speechSilenceTimer?.cancel();
    if (_activeStreamSubscription != null) {
      _activeStreamSubscription!.cancel();
      _activeStreamSubscription = null;
    }
    _completeActiveSend();
    isCallMode = false;
    _handsFreeActive = false;
    _voiceService.stopListening();
    _voiceService.stopSpeaking();
    notifyListeners();
  }

  bool isAppInForeground = true;

  /// App paused / sent to background -> Immediately release microphone & audio focus
  void onAppPaused() {
    isAppInForeground = false;
    _speechSilenceTimer?.cancel();
    _voiceService.stopListening();
    _voiceService.stopSpeaking();
    currentlySpeakingMessageId = null;
    isDictating = false;
    if (isCallMode) {
      isCallMode = false;
    }
    _handsFreeActive = false;
    notifyListeners();
  }

  /// App resumed / brought to foreground
  void onAppResumed() {
    isAppInForeground = true;
    if (darkroomMode && _handsFreeActive) {
      _startListeningLoop();
    } else if (darkroomMode) {
      _startWakeWordStandby();
    }
  }

  /// Start Listening Loop
  Future<void> _startListeningLoop() async {
    if (!isAppInForeground) return; // Prevent background zombie loops!
    if (!isCallMode && !_handsFreeActive && !darkroomMode) return;
    if (_isStartingListening) return;
    _isStartingListening = true;

    try {
      voiceInputText = '';
      dictatedText = '';
      if (_voiceService.isSpeaking) {
        await _voiceService.stopSpeaking();
        await Future.delayed(const Duration(milliseconds: 350));
      }
      if (_voiceService.isListening) {
        await _voiceService.stopListening();
        await Future.delayed(const Duration(milliseconds: 250));
      }
      await _voiceService.startListening();
    } catch (e) {
      debugPrint('[ChatProvider] Error starting listening loop: $e');
    } finally {
      _isStartingListening = false;
    }
  }

  /// Toggle Darkroom (Continuous wake word) standby
  Future<void> toggleDarkroomMode() async {
    darkroomMode = !darkroomMode;
    _handsFreeActive = false;
    isDictating = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkroomModeKey, darkroomMode);

    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    wakeTranscript = '';

    if (darkroomMode) {
      await _voiceService.reInitialize();
      if (!_voiceService.isSpeechEnabled) {
        error =
            'ميزة التعرف على الصوت غير متاحة أو معطلة على هذا الجهاز. يرجى التحقق من إعدادات الميكروفون.';
        darkroomMode = false;
        await prefs.setBool(_darkroomModeKey, false);
        notifyListeners();
        return;
      }
      await _startWakeWordStandby();
    } else {
      wakeTranscript = 'تم إيقاف المساعد الصوتي';
    }
    notifyListeners();
  }

  /// Safely stop all ChatProvider voice services to release Android SpeechRecognizer lock
  Future<void> forceStopVoiceServices() async {
    darkroomMode = false; // Prevents the auto-restart loop from stealing the mic!
    _handsFreeActive = false;
    isCallMode = false;
    isDictating = false;
    _isStartingWakeWord = false;
    _isStartingListening = false;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
  }

  /// Force start wake word standby (used on startup/re-entry)
  Future<void> startWakeWordStandbyForce() async {
    darkroomMode = true;
    _handsFreeActive = false;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    await _voiceService.reInitialize();
    await _startWakeWordStandby();
    notifyListeners();
  }

  /// Resume background voice services if they were enabled by user before modal closed
  Future<void> resumeVoiceServicesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool(_darkroomModeKey) ?? false;
    if (wasEnabled) {
      darkroomMode = true;
      _handsFreeActive = false;
      await _voiceService.reInitialize();
      await _startWakeWordStandby();
      notifyListeners();
    }
  }

  int _lastWakeWordStartTime = 0;

  /// Enter wake word standby listening (uses ENGLISH locale for Hi Ray detection)
  Future<void> _startWakeWordStandby() async {
    if (!isAppInForeground || !darkroomMode || isCallMode || _handsFreeActive) return;

    // Prevent catastrophic cascade if onSpeechEnd and onSpeechError fire simultaneously
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastWakeWordStartTime < 2000) return;
    _lastWakeWordStartTime = now;

    if (_isStartingWakeWord) return;
    _isStartingWakeWord = true;

    try {
      await _voiceService.stopListening();
      await _voiceService.stopSpeaking();

      wakeTranscript = 'في الانتظار... قل "Hi Ray" أو "Hi Sono"';
      notifyListeners();
      await _voiceService.startListeningForWakeWord();
    } finally {
      _isStartingWakeWord = false;
    }
  }

  String _normalizeArabic(String text) {
    // Remove diacritics (تشكيل)
    final diacritics = RegExp(r'[\u064B-\u065F\u0670]');
    String normalized = text.replaceAll(diacritics, '');

    // Normalize Hamzas (أ, إ, آ -> ا)
    normalized = normalized.replaceAll(RegExp(r'[أإآ]'), 'ا');

    // Normalize Teh Marbuta (ة -> ه)
    normalized = normalized.replaceAll('ة', 'ه');

    // Normalize Alef Maksura (ى -> ي)
    normalized = normalized.replaceAll('ى', 'ي');

    // Normalize spaces (multiple spaces/newlines -> single space)
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }

  /// Processes continuous text looking for exclusive wake word "Hi Ray"
  Future<void> _handleWakeWordDetection(String recognizedText) async {
    final text = recognizedText.trim();
    if (text.isEmpty) return;
    wakeTranscript = text;
    notifyListeners();

    final cleanText = _normalizeArabic(text.toLowerCase());

    // Check if the text contains the wake word using our centralized parser
    final isMatch = VoiceCommandParser.isWakeWord(text) || VoiceCommandParser.isWakeWord(cleanText);

    if (isMatch) {
      _handsFreeActive = true;

      // Extract question after wake word if present in same phrase
      final questionPart = VoiceCommandParser.cleanWakeWordPrefix(text);

      if (questionPart.length > 3) {
        // User spoke full question after wake word in one go -> Send full question directly!
        wakeTranscript = 'جارٍ إرسال سؤالك: $questionPart';
        notifyListeners();
        sendMessage(questionPart);
      } else {
        // Standalone wake word call -> Stop mic, play greeting, then re-arm
        wakeTranscript = 'أنا أستمع...';
        notifyListeners();
        _playLocalPhraseAndListen('أنا جاهز للاستماع');
      }
    }
  }

  Future<void> _playLocalPhraseAndListen(String text) async {
    try {
      if (_voiceService.isListening) {
        await _voiceService.stopListening();
        await Future.delayed(const Duration(milliseconds: 200));
      }
      final bytes = await _apiService.fetchTTS(text);
      if (bytes != null) {
        final b64 = base64Encode(bytes);
        await _voiceService.playBase64Audio(b64);
      } else {
        await _voiceService.speak(text);
      }
    } catch (e) {
      debugPrint('[ChatProvider] _playLocalPhraseAndListen error: $e');
      if (isCallMode || (darkroomMode && _handsFreeActive)) {
        _handlePlaybackComplete();
      }
    }
  }

  Future<void> _playLocalPhrase(String text) async {
    await _playLocalPhraseAndListen(text);
  }

  @override
  void dispose() {
    _requestGeneration++;
    _speechSilenceTimer?.cancel();
    if (_activeStreamSubscription != null) {
      _activeStreamSubscription!.cancel();
      _activeStreamSubscription = null;
    }
    _completeActiveSend();
    _voiceService.stopListening();
    _voiceService.stopSpeaking();
    _voiceService.dispose();
    _apiService.dispose();
    super.dispose();
  }
}
