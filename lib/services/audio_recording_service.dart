import 'package:record/record.dart';

class AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();

  /// Check if application has microphone permission
  Future<bool> checkPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording to the specified file path
  Future<void> start(String path) async {
    if (await _recorder.isRecording()) {
      return;
    }
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, bitRate: 128000),
      path: path,
    );
  }

  /// Pause current recording session
  Future<void> pause() async {
    if (await _recorder.isRecording() && !(await _recorder.isPaused())) {
      await _recorder.pause();
    }
  }

  /// Resume current paused recording session
  Future<void> resume() async {
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  /// Stop current recording session and return saved file path
  Future<String?> stop() async {
    return await _recorder.stop();
  }

  /// Get current recording status
  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Get current paused status
  Future<bool> isPaused() async {
    return await _recorder.isPaused();
  }

  /// Dispose of the recorder resource
  void dispose() {
    _recorder.dispose();
  }
}
