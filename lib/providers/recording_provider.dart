import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../services/audio_recording_service.dart';
import '../services/audio_playback_service.dart';

class RecordingItem {
  final String name;
  final String path;
  final Duration duration;
  final int sizeInBytes;
  final DateTime created;

  RecordingItem({
    required this.name,
    required this.path,
    required this.duration,
    required this.sizeInBytes,
    required this.created,
  });

  String get formattedSize {
    final kb = sizeInBytes / 1024;
    final mb = kb / 1024;
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    return '${kb.toStringAsFixed(0)} KB';
  }
}

class RecordingProvider extends ChangeNotifier {
  final AudioRecordingService _recordingService = AudioRecordingService();
  final AudioPlaybackService _playbackService = AudioPlaybackService();

  List<RecordingItem> recordings = [];
  bool isRecordingListLoading = false;

  // Recording State
  bool isRecording = false;
  bool isRecordingPaused = false;
  Duration recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? currentRecordingPath;
  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;

  // Playback State
  String? activePlayingPath;
  bool isPlaying = false;
  bool isPlaybackPaused = false;
  Duration playbackPosition = Duration.zero;
  Duration playbackDuration = Duration.zero;

  // Stream Subscriptions
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playerStateSub;

  RecordingProvider() {
    loadRecordings();
    _initPlaybackListeners();
  }

  void _initPlaybackListeners() {
    _positionSub = _playbackService.positionStream.listen((pos) {
      playbackPosition = pos;
      notifyListeners();
    });

    _durationSub = _playbackService.durationStream.listen((dur) {
      if (dur != null) {
        playbackDuration = dur;
        notifyListeners();
      }
    });

    _playerStateSub = _playbackService.playerStateStream.listen((state) {
      isPlaying = state.playing;
      isPlaybackPaused = !state.playing && state.processingState == ja.ProcessingState.ready;

      if (state.processingState == ja.ProcessingState.completed) {
        isPlaying = false;
        isPlaybackPaused = false;
        playbackPosition = Duration.zero;
        activePlayingPath = null;
        unawaited(_playbackService.stop());
      }
      notifyListeners();
    });
  }

  /// Load recordings list from local app directory
  Future<void> loadRecordings() async {
    isRecordingListLoading = true;
    notifyListeners();

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dirPath = '${docDir.path}/recordings';
      final dir = Directory(dirPath);

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final files = dir.listSync().whereType<File>().toList();
      final prefs = await SharedPreferences.getInstance();

      final List<RecordingItem> loaded = [];

      for (final file in files) {
        final path = file.path;
        if (!path.endsWith('.m4a') && !path.endsWith('.aac') && !path.endsWith('.mp3')) {
          continue;
        }

        final stat = file.statSync();
        final created =
            stat.modified; // Modified serves as creation time since file is not modified post-save
        final size = stat.size;

        // Try getting cached duration to speed up list loading
        final cacheKey = 'duration_$path';
        final cachedMs = prefs.getInt(cacheKey);
        Duration duration = Duration.zero;

        if (cachedMs != null) {
          duration = Duration(milliseconds: cachedMs);
        } else {
          // Fetch duration using temporary player instance to avoid blocking active player
          final tempPlayer = ja.AudioPlayer();
          try {
            final loadedDur = await tempPlayer.setFilePath(path);
            if (loadedDur != null) {
              duration = loadedDur;
              await prefs.setInt(cacheKey, loadedDur.inMilliseconds);
            }
          } catch (_) {
            duration = Duration.zero;
          } finally {
            await tempPlayer.dispose();
          }
        }

        loaded.add(
          RecordingItem(
            name: file.uri.pathSegments.last,
            path: path,
            duration: duration,
            sizeInBytes: size,
            created: created,
          ),
        );
      }

      // Sort by newest first
      loaded.sort((a, b) => b.created.compareTo(a.created));
      recordings = loaded;
    } catch (_) {
      // Fail silently, list stays empty
    } finally {
      isRecordingListLoading = false;
      notifyListeners();
    }
  }

  /// Request runtime permission for Microphone
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Start Recording session
  Future<bool> startRecording() async {
    if (isRecording) return true;
    if (_isStartingRecording) return false;
    _isStartingRecording = true;
    try {
      final hasPermission = await _recordingService.checkPermission();
      if (!hasPermission) {
        final granted = await requestMicPermission();
        if (!granted) return false;
      }

      // Stop active playback if any
      if (activePlayingPath != null) {
        await stopPlayback();
      }

      final docDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${docDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${recordingsDir.path}/Rec_$timestamp.m4a';

      currentRecordingPath = filePath;
      await _recordingService.start(filePath);

      isRecording = true;
      isRecordingPaused = false;
      recordingDuration = Duration.zero;

      _startRecordingTimer();
      notifyListeners();
      return true;
    } catch (_) {
      isRecording = false;
      isRecordingPaused = false;
      recordingDuration = Duration.zero;
      currentRecordingPath = null;
      notifyListeners();
      return false;
    } finally {
      _isStartingRecording = false;
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      recordingDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Pause current recording session
  Future<void> pauseRecording() async {
    try {
      await _recordingService.pause();
      isRecordingPaused = true;
      _recordingTimer?.cancel();
      notifyListeners();
    } catch (_) {}
  }

  /// Resume current paused recording session
  Future<void> resumeRecording() async {
    try {
      await _recordingService.resume();
      isRecordingPaused = false;
      _startRecordingTimer();
      notifyListeners();
    } catch (_) {}
  }

  /// Stop current recording session
  Future<void> stopRecording() async {
    if (_isStoppingRecording || (!isRecording && currentRecordingPath == null)) return;
    _isStoppingRecording = true;
    _recordingTimer?.cancel();
    try {
      final savedPath = await _recordingService.stop();
      isRecording = false;
      isRecordingPaused = false;
      recordingDuration = Duration.zero;
      currentRecordingPath = null;
      notifyListeners();

      // Read final duration and cache it immediately
      if (savedPath != null) {
        final prefs = await SharedPreferences.getInstance();
        final tempPlayer = ja.AudioPlayer();
        try {
          final dur = await tempPlayer.setFilePath(savedPath);
          if (dur != null) {
            await prefs.setInt('duration_$savedPath', dur.inMilliseconds);
          }
        } finally {
          await tempPlayer.dispose();
        }
      }

      await loadRecordings();
    } catch (_) {
      isRecording = false;
      isRecordingPaused = false;
      recordingDuration = Duration.zero;
      currentRecordingPath = null;
      notifyListeners();
    } finally {
      _isStoppingRecording = false;
    }
  }

  /// Play a saved recording file
  Future<void> playRecording(RecordingItem item) async {
    if (activePlayingPath == item.path) {
      if (isPlaybackPaused) {
        await resumePlayback();
      } else if (isPlaying) {
        await pausePlayback();
      }
      return;
    }

    try {
      await _playbackService.stop();
      activePlayingPath = item.path;
      playbackPosition = Duration.zero;
      playbackDuration = item.duration;
      notifyListeners();

      await _playbackService.play(item.path);
    } catch (_) {
      activePlayingPath = null;
      isPlaying = false;
      notifyListeners();
    }
  }

  /// Pause playback
  Future<void> pausePlayback() async {
    await _playbackService.pause();
  }

  /// Resume playback
  Future<void> resumePlayback() async {
    await _playbackService.resume();
  }

  /// Stop playback
  Future<void> stopPlayback() async {
    await _playbackService.stop();
    activePlayingPath = null;
    isPlaying = false;
    isPlaybackPaused = false;
    playbackPosition = Duration.zero;
    notifyListeners();
  }

  /// Seek to duration
  Future<void> seekPlayback(Duration pos) async {
    await _playbackService.seek(pos);
  }

  /// Share recording item
  Future<void> shareRecording(RecordingItem item, {required Rect sharePositionOrigin}) async {
    final file = XFile(item.path);
    await Share.shareXFiles([file], text: item.name, sharePositionOrigin: sharePositionOrigin);
  }

  /// Rename recording item
  Future<void> renameRecording(RecordingItem item, String newName) async {
    var cleanedName = newName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceFirst(RegExp(r'^\.+'), '');
    if (cleanedName.isEmpty) return;
    if (cleanedName.length > 80) {
      cleanedName = cleanedName.substring(0, 80).trim();
    }

    // Preserve extension
    final ext = item.path.split('.').last;
    if (!cleanedName.endsWith('.$ext')) {
      cleanedName = '$cleanedName.$ext';
    }

    try {
      if (activePlayingPath == item.path) {
        await stopPlayback();
      }
      final file = File(item.path);
      var newPath = '${file.parent.path}/$cleanedName';
      if (newPath != item.path && await File(newPath).exists()) {
        final base = cleanedName.substring(0, cleanedName.length - ext.length - 1);
        newPath = '${file.parent.path}/${base}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      }
      await file.rename(newPath);

      // Clean cache for old path, cache for new path
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('duration_${item.path}');
      await prefs.setInt('duration_$newPath', item.duration.inMilliseconds);

      await loadRecordings();
    } catch (_) {}
  }

  /// Delete recording item
  Future<void> deleteRecording(RecordingItem item) async {
    try {
      if (activePlayingPath == item.path) {
        await stopPlayback();
      }

      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }

      // Clear cached duration
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('duration_${item.path}');

      await loadRecordings();
    } catch (_) {}
  }

  /// Permanently removes all locally stored recordings and duration metadata.
  Future<void> deleteAllRecordings() async {
    _recordingTimer?.cancel();
    if (isRecording) {
      try {
        await _recordingService.stop();
      } catch (_) {}
    }
    await stopPlayback();

    final docDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${docDir.path}/recordings');
    if (await recordingsDir.exists()) {
      await for (final entity in recordingsDir.list(followLinks: false)) {
        if (entity is File) await entity.delete();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final durationKeys = prefs.getKeys().where((key) => key.startsWith('duration_'));
    for (final key in durationKeys) {
      await prefs.remove(key);
    }

    recordings = [];
    isRecording = false;
    isRecordingPaused = false;
    recordingDuration = Duration.zero;
    currentRecordingPath = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _recordingService.dispose();
    _playbackService.dispose();
    super.dispose();
  }
}
