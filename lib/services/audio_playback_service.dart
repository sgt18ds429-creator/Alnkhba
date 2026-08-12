import 'package:just_audio/just_audio.dart';

class AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  /// Get position stream
  Stream<Duration> get positionStream => _player.positionStream;

  /// Get total duration stream
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Get player state stream
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Whether player is currently playing
  bool get isPlaying => _player.playing;

  /// Load and play a local audio file
  Future<void> play(String path) async {
    try {
      await _player.setFilePath(path);
      await _player.play();
    } catch (_) {
      rethrow;
    }
  }

  /// Pause current playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.play();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to a specific duration
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Dispose player resource
  void dispose() {
    _player.dispose();
  }
}
