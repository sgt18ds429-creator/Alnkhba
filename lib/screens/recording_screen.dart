import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../providers/recording_provider.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import '../widgets/recording_waveform.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> with WidgetsBindingObserver {
  final TextEditingController _renameController = TextEditingController();
  RecordingProvider? _recordingProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordingProvider = Provider.of<RecordingProvider>(context, listen: false);
  }

  Future<void> _stopMediaOnExit() async {
    final provider = _recordingProvider;
    if (provider == null) return;
    if (provider.isRecording) await provider.stopRecording();
    if (provider.activePlayingPath != null) await provider.stopPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopMediaOnExit());
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(d.inHours);
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  String _formatShortDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return '${twoDigits(d.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showRenameDialog(BuildContext context, RecordingProvider provider, RecordingItem item) {
    // Remove extension for easier editing
    final nameWithoutExt = item.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    _renameController.text = nameWithoutExt;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          title: Text(
            'إعادة تسمية التسجيل',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'Cairo',
              fontSize: 16.0,
            ),
          ),
          content: TextField(
            controller: _renameController,
            autofocus: true,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              hintText: 'اسم الملف الجديد...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(12.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = _renameController.text.trim();
                if (newName.isNotEmpty) {
                  provider.renameRecording(item, newName);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              child: const Text(
                'حفظ',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, RecordingProvider provider, RecordingItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          title: Text(
            'حذف التسجيل؟',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'Cairo',
              fontSize: 16.0,
            ),
          ),
          content: Text(
            'هل أنت متأكد من رغبتك في حذف "${item.name}"؟ لا يمكن التراجع عن هذا الإجراء.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'Cairo',
              fontSize: 13.0,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                provider.deleteRecording(item);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              child: const Text(
                'حذف',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopMediaOnExit());
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingProvider = Provider.of<RecordingProvider>(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'سجل المحاضرات والتقارير',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 18.0,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
            onPressed: () => Navigator.pop(context),
          ),
          elevation: 0,
        ),
        body: Column(
          children: [
            // Section 1: Recorder Panel
            Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.6),
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFC5A059).withOpacity(0.15),
                    blurRadius: 20.0,
                    spreadRadius: 2.0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    recordingProvider.isRecording
                        ? (recordingProvider.isRecordingPaused ? 'التسجيل معلق' : 'جارٍ التسجيل...')
                        : 'جاهز للتسجيل',
                    style: TextStyle(
                      color: recordingProvider.isRecording
                          ? (recordingProvider.isRecordingPaused
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.error)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'Cairo',
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12.0),

                  // Digital Timer
                  Text(
                    _formatDuration(recordingProvider.recordingDuration),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 42.0,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16.0),

                  // Waveform Visualizer
                  RecordingWaveform(
                    isRecording: recordingProvider.isRecording,
                    isPaused: recordingProvider.isRecordingPaused,
                    color: const Color(0xFFC5A059),
                  ),
                  const SizedBox(height: 24.0),

                  // Recorder Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (recordingProvider.isRecording) ...[
                        // Pause / Resume Button
                        IconButton(
                          onPressed: () {
                            if (recordingProvider.isRecordingPaused) {
                              recordingProvider.resumeRecording();
                            } else {
                              recordingProvider.pauseRecording();
                            }
                          },
                          icon: Icon(
                            recordingProvider.isRecordingPaused ? Icons.play_arrow : Icons.pause,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                            minimumSize: const Size(54, 54),
                          ),
                        ),
                        const SizedBox(width: 24.0),

                        // Stop Button
                        IconButton(
                          onPressed: () => recordingProvider.stopRecording(),
                          icon: Icon(Icons.stop, color: Theme.of(context).colorScheme.onError),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.error,
                            minimumSize: const Size(64, 64),
                          ),
                        ),
                      ] else ...[
                        // Start Record Button
                        IconButton(
                          onPressed: () => recordingProvider.startRecording(),
                          icon: Icon(
                            Icons.mic,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 28.0,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            minimumSize: const Size(68, 68),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Section 2: Header Label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'التسجيلات المحفوظة',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'Cairo',
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Section 3: Recordings List
            Expanded(
              child: recordingProvider.isRecordingListLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : recordingProvider.recordings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_none,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          ),
                          const SizedBox(height: 12.0),
                          Text(
                            'لا توجد تسجيلات بعد',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontFamily: 'Cairo',
                              fontSize: 14.0,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                      itemCount: recordingProvider.recordings.length,
                      itemBuilder: (context, index) {
                        final item = recordingProvider.recordings[index];
                        final isCurrentPlaying = recordingProvider.activePlayingPath == item.path;

                        return Card(
                          color: isCurrentPlaying
                              ? Theme.of(context).colorScheme.surfaceContainerHighest
                              : Theme.of(context).colorScheme.surfaceContainer,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 10.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                            side: BorderSide(
                              color: isCurrentPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                              width: 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isCurrentPlaying
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: IconButton(
                                icon: Icon(
                                  isCurrentPlaying && recordingProvider.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: isCurrentPlaying
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.primary,
                                  size: 18.0,
                                ),
                                onPressed: () => recordingProvider.playRecording(item),
                              ),
                            ),
                            title: Text(
                              item.name
                                  .replaceAll('.m4a', '')
                                  .replaceAll('.aac', '')
                                  .replaceAll('.mp3', ''),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _formatShortDuration(item.duration),
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      item.formattedSize,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('yyyy/MM/dd hh:mm a').format(item.created),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant.withOpacity(0.8),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Action buttons in a popup menu
                                PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    side: BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  onSelected: (value) async {
                                    switch (value) {
                                      case 'summarize':
                                        try {
                                          final file = File(item.path);
                                          final exists = await file.exists();
                                          if (exists) {
                                            final length = await file.length();
                                            if (length > 12 * 1024 * 1024) {
                                              throw Exception(
                                                'التسجيل أكبر من 12 MB. قصّ التسجيل أو شارك مقطعاً أقصر.',
                                              );
                                            }
                                            final bytes = await file.readAsBytes();
                                            final base64 = base64Encode(bytes);

                                            // Determine mime type
                                            String mime = 'audio/mp4';
                                            if (item.path.endsWith('.aac')) mime = 'audio/aac';
                                            if (item.path.endsWith('.mp3')) mime = 'audio/mpeg';

                                            if (!context.mounted) return;
                                            final chatProvider = Provider.of<ChatProvider>(
                                              context,
                                              listen: false,
                                            );

                                            // Add as audio attachment
                                            chatProvider.addAttachment(
                                              AttachmentItem(
                                                base64: base64,
                                                mime: mime,
                                                name: item.name,
                                                type: 'audio',
                                                bytes: bytes,
                                              ),
                                            );

                                            // Pre-fill prompt
                                            chatProvider.setPrefilledText(
                                              "لخص لي هذا التسجيل الصوتي للمحاضرة بالتفصيل:",
                                            );

                                            if (context.mounted) {
                                              Navigator.of(context).pop(); // Go back to ChatScreen
                                            }
                                          } else {
                                            throw Exception('الملف غير موجود على القرص المحلي');
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'فشل في قراءة ملف التسجيل: $e',
                                                  style: const TextStyle(fontFamily: 'Cairo'),
                                                ),
                                                backgroundColor: Colors.redAccent,
                                              ),
                                            );
                                          }
                                        }
                                        break;
                                      case 'share':
                                        try {
                                          final renderObject = context.findRenderObject();
                                          final screenSize = MediaQuery.sizeOf(context);
                                          final shareOrigin = renderObject is RenderBox
                                              ? renderObject.localToGlobal(Offset.zero) &
                                                    renderObject.size
                                              : Rect.fromLTWH(
                                                  0,
                                                  0,
                                                  screenSize.width,
                                                  screenSize.height,
                                                );
                                          await recordingProvider.shareRecording(
                                            item,
                                            sharePositionOrigin: shareOrigin,
                                          );
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'تعذرت مشاركة التسجيل حالياً.',
                                                  style: TextStyle(fontFamily: 'Cairo'),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                        break;
                                      case 'rename':
                                        _showRenameDialog(context, recordingProvider, item);
                                        break;
                                      case 'delete':
                                        _showDeleteDialog(context, recordingProvider, item);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'summarize',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.summarize,
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'لخص في المحادثة 📝',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontFamily: 'Cairo',
                                              fontSize: 12.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'share',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.share,
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'مشاركة',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontFamily: 'Cairo',
                                              fontSize: 12.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.edit,
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'إعادة تسمية',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurface,
                                              fontFamily: 'Cairo',
                                              fontSize: 12.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            color: Theme.of(context).colorScheme.error,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'حذف',
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.error,
                                              fontFamily: 'Cairo',
                                              fontSize: 12.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Persistent Playback Bottom Panel
            if (recordingProvider.activePlayingPath != null)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Small Play/Pause
                        IconButton(
                          onPressed: () {
                            if (recordingProvider.isPlaying) {
                              recordingProvider.pausePlayback();
                            } else {
                              recordingProvider.resumePlayback();
                            }
                          },
                          icon: Icon(
                            recordingProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(width: 12.0),

                        // File name and timeline text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recordingProvider.recordings
                                    .firstWhere(
                                      (r) => r.path == recordingProvider.activePlayingPath,
                                      orElse: () => RecordingItem(
                                        name: 'ملف غير معروف',
                                        path: '',
                                        duration: Duration.zero,
                                        sizeInBytes: 0,
                                        created: DateTime.now(),
                                      ),
                                    )
                                    .name
                                    .replaceAll('.m4a', ''),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontFamily: 'Cairo',
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2.0),
                              Row(
                                children: [
                                  Text(
                                    _formatShortDuration(recordingProvider.playbackPosition),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    ' / ',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    _formatShortDuration(recordingProvider.playbackDuration),
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Close/Stop Button
                        IconButton(
                          onPressed: () => recordingProvider.stopPlayback(),
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),

                    // Slider Timeline
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        thumbColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        value: recordingProvider.playbackPosition.inMilliseconds.toDouble().clamp(
                          0.0,
                          recordingProvider.playbackDuration.inMilliseconds.toDouble() > 0
                              ? recordingProvider.playbackDuration.inMilliseconds.toDouble()
                              : 1.0,
                        ),
                        max: recordingProvider.playbackDuration.inMilliseconds.toDouble() > 0
                            ? recordingProvider.playbackDuration.inMilliseconds.toDouble()
                            : 1.0,
                        onChanged: (val) {
                          recordingProvider.seekPlayback(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
