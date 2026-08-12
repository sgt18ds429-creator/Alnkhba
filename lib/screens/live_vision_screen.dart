import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';

class LiveVisionScreen extends StatefulWidget {
  const LiveVisionScreen({super.key});

  @override
  State<LiveVisionScreen> createState() => _LiveVisionScreenState();
}

class _LiveVisionScreenState extends State<LiveVisionScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  int _cameraGeneration = 0;
  bool _isInitializing = true;
  bool _isAnalyzing = false;
  bool _autoAnalysisActive = false;
  bool _analysisLoopActive = false; // علم التحكم في حلقة التحليل
  int _analysisGeneration = 0;
  String _analysisResult =
      'لا تُرسل الكاميرا أي صورة تلقائياً. التقط لقطة واحدة أو فعّل التحليل الدوري بعد إزالة أي بيانات تعرّف المريض.';
  String? _lastCapturedBase64;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  Future<void> _initializeCamera() async {
    final generation = ++_cameraGeneration;
    CameraController? pendingController;
    try {
      final cameras = await availableCameras();
      if (!mounted || generation != _cameraGeneration) return;
      if (cameras.isEmpty) {
        setState(() {
          _error = 'لا توجد كاميرا متاحة على هذا الجهاز.';
          _isInitializing = false;
        });
        return;
      }

      // Select back camera
      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      pendingController = CameraController(backCamera, ResolutionPreset.medium, enableAudio: false);

      await pendingController.initialize();
      try {
        await pendingController.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted || generation != _cameraGeneration) {
        await pendingController.dispose();
        return;
      }

      final previousController = _controller;
      _controller = pendingController;
      pendingController = null;
      if (previousController != null) {
        await previousController.dispose();
      }
      setState(() {
        _error = null;
        _isInitializing = false;
      });
    } catch (e) {
      await pendingController?.dispose();
      if (mounted && generation == _cameraGeneration) {
        setState(() {
          _error = 'خطأ أثناء تشغيل الكاميرا: $e';
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraGeneration++;
    _analysisGeneration++;
    _analysisLoopActive = false; // إيقاف حلقة التحليل فوراً
    _lastCapturedBase64 = null;
    WidgetsBinding.instance.removeObserver(this);
    final cameraController = _controller;
    _controller = null;
    if (cameraController != null) {
      unawaited(cameraController.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _cameraGeneration++;
      _analysisGeneration++;
      // Periodic capture never resumes implicitly after backgrounding.
      _analysisLoopActive = false;
      _autoAnalysisActive = false;
      _analysisResult =
          'توقف التحليل الدوري عند مغادرة التطبيق. شغّله مجدداً إذا رغبت بعد إزالة بيانات المريض.';
      final cameraController = _controller;
      _controller = null; // منع استخدام الـ controller بعد التدمير
      if (cameraController != null) {
        unawaited(cameraController.dispose());
      }
    } else if (state == AppLifecycleState.resumed) {
      final cameraController = _controller;
      if (cameraController == null || !cameraController.value.isInitialized) {
        setState(() {
          _isInitializing = true;
          _error = null;
        });
        unawaited(_initializeCamera());
      }
    }
  }

  // Automatic Background Analysis Loop
  Future<void> _startAnalysisLoop() async {
    if (_analysisLoopActive) return;
    _analysisLoopActive = true;
    final generation = ++_analysisGeneration;
    while (_analysisLoopActive && generation == _analysisGeneration && mounted) {
      await Future.delayed(const Duration(seconds: 10));
      if (!_analysisLoopActive || generation != _analysisGeneration || !mounted) break;

      if (_autoAnalysisActive &&
          !_isAnalyzing &&
          _controller != null &&
          _controller!.value.isInitialized &&
          !_controller!.value.isTakingPicture) {
        await _captureAndAnalyze();
      }
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_isAnalyzing ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isTakingPicture) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    XFile? capturedPhoto;
    try {
      final photo = await _controller!.takePicture();
      capturedPhoto = photo;
      final fileLength = await photo.length();
      if (fileLength > 8 * 1024 * 1024) {
        throw Exception('حجم اللقطة أكبر من 8 MB');
      }
      final bytes = await photo.readAsBytes();
      final base64Image = base64Encode(bytes);

      if (!mounted) return;
      _lastCapturedBase64 = base64Image;

      final provider = Provider.of<ChatProvider>(context, listen: false);
      await provider.ensureInitialized();
      final response = await provider.apiService.sendChat(
        message:
            "حلّل هذه اللقطة لأغراض تعليمية فقط. صف المرئي بوضوح في 3-4 جمل، اذكر حدود جودة الصورة، ولا تقدم تشخيصاً نهائياً أو قراراً علاجياً.",
        history: [],
        userId: provider.userId,
        imageBase64: base64Image,
        imageMime: 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          _analysisResult =
              'تحليل تعليمي مولّد بالذكاء الاصطناعي — غير مخصص للتشخيص\n\n${response['reply'] ?? 'لم يتم الحصول على تحليل.'}';
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysisResult = 'خطأ في التحليل التلقائي: ${e.toString().replaceAll('Exception:', '')}';
          _isAnalyzing = false;
        });
      }
    } finally {
      if (capturedPhoto != null) {
        try {
          final file = File(capturedPhoto.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  void _toggleAutomaticAnalysis() {
    setState(() {
      _autoAnalysisActive = !_autoAnalysisActive;
      if (_autoAnalysisActive) {
        _analysisResult =
            'التحليل الدوري نشط: ستُرسل لقطة كل 10 ثوانٍ حتى إيقافه أو مغادرة الصفحة.';
      } else {
        _analysisGeneration++;
        _analysisLoopActive = false;
      }
    });
    if (_autoAnalysisActive) unawaited(_startAnalysisLoop());
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. Camera Preview or Status
            Positioned.fill(
              child: _isInitializing
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 14,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        // HUD Overlay
                        CustomPaint(
                          painter: _HudPainter(color: Theme.of(context).colorScheme.primary),
                        ),
                        // Scanning Line
                        if (_autoAnalysisActive) const _ScanningLineOverlay(),
                      ],
                    ),
            ),

            // Top Status Bar Overlay (Back Button)
            Positioned(
              top: 40.0,
              right: 16.0,
              left: 16.0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _autoAnalysisActive
                              ? Icons.cloud_upload_outlined
                              : Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _autoAnalysisActive
                              ? 'إرسال دوري كل 10 ثوانٍ'
                              : 'الكاميرا جاهزة — لا يوجد إرسال',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Panel: Analysis Results & Actions
            Positioned(
              bottom: 24.0,
              left: 16.0,
              right: 16.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.75),
                      borderRadius: BorderRadius.circular(24.0),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Analysis Title & Loader indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'تحليل بصري تعليمي',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            if (_isAnalyzing)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              )
                            else
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _autoAnalysisActive
                                      ? Theme.of(context).colorScheme.tertiary
                                      : Theme.of(context).colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Result Text area
                        Container(
                          constraints: const BoxConstraints(maxHeight: 120),
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _analysisResult,
                              style: const TextStyle(
                                color: Color(0xFFF1F5F9),
                                fontSize: 12.0,
                                height: 1.45,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          onPressed: _isAnalyzing ? null : _captureAndAnalyze,
                          icon: const Icon(Icons.center_focus_strong, size: 18),
                          label: Text(
                            _isAnalyzing ? 'جارٍ تحليل اللقطة...' : 'التقاط وتحليل مرة واحدة',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Actions Row
                        Row(
                          children: [
                            // Pause / Resume Auto Scan button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _toggleAutomaticAnalysis,
                                icon: Icon(
                                  _autoAnalysisActive
                                      ? Icons.stop_circle_outlined
                                      : Icons.autorenew,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                label: Text(
                                  _autoAnalysisActive ? 'إيقاف الدوري' : 'تشغيل الدوري',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Send to Chat button
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _lastCapturedBase64 == null
                                    ? null
                                    : () {
                                        final userMsg = Message(
                                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                                          role: 'user',
                                          text: 'تحليل الرؤية الحية الفوري.',
                                          attachments: [
                                            AttachmentItem(
                                              base64: _lastCapturedBase64!,
                                              mime: 'image/jpeg',
                                              name: 'live_capture.jpg',
                                              type: 'image',
                                            ),
                                          ],
                                        );
                                        final modelMsg = Message(
                                          id: (DateTime.now().millisecondsSinceEpoch + 1)
                                              .toString(),
                                          role: 'model',
                                          text: _analysisResult,
                                        );
                                        provider.injectCustomMessages(userMsg, modelMsg);
                                        Navigator.pop(context);
                                      },
                                icon: Icon(
                                  Icons.send,
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  size: 16,
                                ),
                                label: Text(
                                  'إرسال للمحادثة',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  final Color color;

  _HudPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final length = size.width * 0.15;
    final w = size.width;
    final h = size.height;

    // Top-Left
    canvas.drawLine(const Offset(20, 20), Offset(20, 20 + length), paint);
    canvas.drawLine(const Offset(20, 20), Offset(20 + length, 20), paint);

    // Top-Right
    canvas.drawLine(Offset(w - 20, 20), Offset(w - 20, 20 + length), paint);
    canvas.drawLine(Offset(w - 20, 20), Offset(w - 20 - length, 20), paint);

    // Bottom-Left
    canvas.drawLine(Offset(20, h - 20), Offset(20, h - 20 - length), paint);
    canvas.drawLine(Offset(20, h - 20), Offset(20 + length, h - 20), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w - 20, h - 20), Offset(w - 20, h - 20 - length), paint);
    canvas.drawLine(Offset(w - 20, h - 20), Offset(w - 20 - length, h - 20), paint);

    // Crosshair
    final center = Offset(w / 2, h / 2 - 50);
    paint.strokeWidth = 1.0;
    paint.color = color.withOpacity(0.4);
    canvas.drawCircle(center, 40, paint);
    canvas.drawLine(Offset(center.dx - 10, center.dy), Offset(center.dx + 10, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - 10), Offset(center.dx, center.dy + 10), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanningLineOverlay extends StatefulWidget {
  const _ScanningLineOverlay();

  @override
  State<_ScanningLineOverlay> createState() => _ScanningLineOverlayState();
}

class _ScanningLineOverlayState extends State<_ScanningLineOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.1,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Positioned(
          top: MediaQuery.of(context).size.height * _animation.value,
          left: 0,
          right: 0,
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.tertiary.withOpacity(0.8),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
