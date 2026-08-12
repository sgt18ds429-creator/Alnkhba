import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/history_drawer.dart';
import '../widgets/wave_indicator.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/voice_assistant_modal.dart';
import 'recording_screen.dart';
import 'live_vision_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _showGlassMenu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      chatProvider.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      chatProvider.onAppResumed();
    }
  }

  // Resize image bytes natively to max 1080px width to prevent OOM on 50MP+ devices
  Future<Uint8List> _resizeImageBytes(Uint8List rawBytes) async {
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(rawBytes, targetWidth: 1080, allowUpscaling: false);
      frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        return data.buffer.asUint8List();
      }
      throw const FormatException('تعذر تحويل الصورة إلى صيغة آمنة.');
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
  }

  // Pick image helper - with native GPU resizing & compression
  Future<void> _pickImage(ImageSource source, ChatProvider provider) async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null || !mounted) return;
      if (await file.length() > 20 * 1024 * 1024) {
        throw Exception('الصورة كبيرة جداً. اختر صورة أصغر من 20 MB.');
      }
      final rawBytes = await file.readAsBytes();
      final resizedBytes = await _resizeImageBytes(rawBytes);
      final base64 = base64Encode(resizedBytes);
      provider.selectImage(base64, _detectImageMime(resizedBytes), file.name, bytes: resizedBytes);
    } catch (e) {
      debugPrint('[ChatScreen] Image pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception:', '').trim())));
      }
    }
  }

  String _detectImageMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  // Pick one PDF safely. The original bytes are analysed by the backend.
  Future<void> _pickPdf(ChatProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: false,
      );
      if (result != null) {
        for (final file in result.files) {
          if (!mounted) return;
          if (file.size > 12 * 1024 * 1024) {
            throw Exception('ملف PDF أكبر من 12 MB. اختر ملفاً أصغر.');
          }
          Uint8List? fileBytes = file.bytes;
          if (fileBytes == null && file.path != null) {
            final f = File(file.path!);
            if (await f.exists()) {
              final len = await f.length();
              if (len > 12 * 1024 * 1024) {
                throw Exception('ملف PDF أكبر من 12 MB. اختر ملفاً أصغر.');
              }
              fileBytes = await f.readAsBytes();
            }
          }
          if (fileBytes != null && fileBytes.isNotEmpty) {
            final isPdf =
                fileBytes.length >= 5 &&
                fileBytes[0] == 0x25 &&
                fileBytes[1] == 0x50 &&
                fileBytes[2] == 0x44 &&
                fileBytes[3] == 0x46 &&
                fileBytes[4] == 0x2D;
            if (!isPdf) {
              throw Exception('الملف المحدد ليس ملف PDF صالحاً.');
            }
            final base64 = base64Encode(fileBytes);
            provider.selectPdf(base64, file.name, bytes: fileBytes);
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] PDF pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception:', '').trim())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    // Auto-scroll on new messages
    if (chatProvider.isLoading || chatProvider.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final currentScroll = _scrollController.position.pixels;
          if ((maxScroll - currentScroll).abs() < 120 || chatProvider.isLoading) {
            _scrollController.jumpTo(maxScroll);
          }
        }
      });
    }

    // Intercept dictation speech-to-text / Gemini audio transcription result
    if (chatProvider.dictatedText.isNotEmpty) {
      final text = chatProvider.dictatedText;
      if (_textController.text != text) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: _textController.text.length),
          );
          chatProvider.clearDictatedText();
        });
      }
    }

    // Intercept prefilled recording/summary prompts
    if (chatProvider.prefilledText != null && chatProvider.prefilledText!.isNotEmpty) {
      final text = chatProvider.prefilledText!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textController.text = text;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        chatProvider.consumePrefilledText();
      });
    }

    final bool hasAttachment = chatProvider.selectedAttachments.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: false,
        endDrawer: const HistoryDrawer(),
        appBar: AppBar(
          backgroundColor: const Color(0xFF020814).withOpacity(0.85),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(color: const Color(0xFF38BDF8).withOpacity(0.2), height: 1.0),
          ),
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF087CFF).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF087CFF).withOpacity(0.5), width: 1.5),
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Image.asset(
                    'assets/logo_icon_v2.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.school, color: Color(0xFF38BDF8)),
                  ),
                ),
              ),
            ),
          ),
          leadingWidth: 60,
          title: Column(
            children: [
              const Text(
                'EliteRadiIQ',
                style: TextStyle(
                  color: Color(0xFFF5F7FA),
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'مساعد نخبة الأشعة',
                style: TextStyle(color: Color(0xFFAAB7C8), fontSize: 11.0),
              ),
            ],
          ),
          actions: [
            if (chatProvider.activeConsultantRoom != null)
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Color(0xFFFFB4AB), size: 22),
                tooltip: 'الخروج من الغرفة الأكاديمية',
                onPressed: () {
                  chatProvider.clearConsultantRoom();
                  chatProvider.clearChat();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('تم الخروج من الغرفة الأكاديمية')));
                },
              ),
            // Medical Disclaimer Info Button
            IconButton(
              icon: const Icon(Icons.info_outline, color: Color(0xFFD9A441), size: 22),
              tooltip: 'تنويه طبي وإخلاء مسؤولية',
              onPressed: () => _showMedicalDisclaimer(context),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFAAB7C8), size: 22),
              tooltip: 'مسح المحادثة',
              onPressed: () => chatProvider.clearChat(),
            ),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Color(0xFFF5F7FA), size: 26),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            // 1. Main Chat Interface
            Column(
              children: [
                // Message List Area
                Expanded(
                  child: chatProvider.messages.isEmpty && !chatProvider.isLoading
                      ? _buildWelcomeScreen(chatProvider)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16.0),
                          itemCount: chatProvider.messages.length,
                          itemBuilder: (context, index) {
                            return ChatBubble(message: chatProvider.messages[index]);
                          },
                        ),
                ),

                // Loader / Typing Indicator
                if (chatProvider.isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/logo_icon_v2.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4.0),
                              topRight: Radius.circular(16.0),
                              bottomLeft: Radius.circular(16.0),
                              bottomRight: Radius.circular(16.0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const TypingIndicator(),
                              const SizedBox(width: 12),
                              Text(
                                chatProvider.activeRequestHasImage
                                    ? 'جارٍ تحليل الصورة...'
                                    : 'يتم التفكير...',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12.0,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error Card Alert
                if (chatProvider.error != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chatProvider.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontSize: 12.5,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            chatProvider.clearError();
                          },
                          child: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Attachment Preview Bar
                if (hasAttachment)
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: chatProvider.selectedAttachments.length,
                      itemBuilder: (context, idx) {
                        final a = chatProvider.selectedAttachments[idx];
                        Widget previewWidget;
                        if (a.type == 'image') {
                          previewWidget = Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.primary),
                              image: DecorationImage(
                                image: MemoryImage(a.bytes ?? base64Decode(a.base64)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        } else if (a.type == 'pdf') {
                          previewWidget = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a.name.length > 10 ? '${a.name.substring(0, 10)}...' : a.name,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 10,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else {
                          // Audio
                          previewWidget = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.audiotrack,
                                  color: Theme.of(context).colorScheme.secondary,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a.name.length > 10 ? '${a.name.substring(0, 10)}...' : a.name,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.secondary,
                                    fontSize: 10,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              previewWidget,
                              Positioned(
                                top: -6,
                                left: -6,
                                child: GestureDetector(
                                  onTap: () => chatProvider.removeAttachment(idx),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                // Footer Input Bar
                _buildFooterBar(chatProvider, hasAttachment),
              ],
            ),

            // 2. Call Mode Overlay Layer (Continuous Voice Loop UI)
            if (chatProvider.isCallMode || chatProvider.isHandsFreeActive)
              _buildCallOverlay(chatProvider),

            // 3. Darkroom Wake Word Overlay Standby
            if (chatProvider.darkroomMode &&
                !chatProvider.isCallMode &&
                !chatProvider.isHandsFreeActive)
              _buildDarkroomStandby(chatProvider),

            // 4. Glassmorphism Attachments Menu dismiss barrier
            if (_showGlassMenu)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showGlassMenu = false;
                    });
                  },
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox.expand(),
                ),
              ),
            if (_showGlassMenu) _buildGlassmorphicMenu(chatProvider),
          ],
        ),
      ),
    );
  }

  // Welcome Screen
  Widget _buildWelcomeScreen(ChatProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Large rounded Welcome Card
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF08182A).withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF087CFF).withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'أهلاً بك',
                      style: TextStyle(
                        color: Color(0xFFF5F7FA),
                        fontSize: 28.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.auto_awesome, color: const Color(0xFFD9A441), size: 28),
                  ],
                ),
                Container(
                  width: 60,
                  height: 3,
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9A441),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'اسأل أي سؤال في تقنيات الأشعة، التصوير الطبي، CT، MRI، أو الحماية الإشعاعية.',
                  style: TextStyle(color: Color(0xFFF5F7FA), fontSize: 15.0, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Suggested action prompts
          Column(
            children: [
              _buildQuickAction('اشرح بروتوكول CT الصدر', Icons.album_outlined, provider),
              const SizedBox(height: 12),
              _buildQuickAction('ما هي أوضاع تصوير الجمجمة؟', Icons.accessibility_new, provider),
              const SizedBox(height: 12),
              _buildQuickAction('ما هي عوامل kVp و mAs؟', Icons.tune, provider),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String text, IconData icon, ChatProvider provider) {
    return InkWell(
      borderRadius: BorderRadius.circular(16.0),
      onTap: () async {
        _textController.clear();
        await provider.sendMessage(text);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1D32).withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF087CFF).withOpacity(0.2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF087CFF).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF087CFF).withOpacity(0.3)),
              ),
              child: Icon(icon, color: const Color(0xFF38BDF8), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFFF5F7FA),
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: const Color(0xFF38BDF8).withOpacity(0.7),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  // Footer bar with buttons and input field
  Widget _buildFooterBar(ChatProvider provider, bool hasAttachment) {
    final isListening = provider.isListening;
    final isCallActive = provider.isCallMode;
    final isDictating = provider.isDictating;
    final darkroomMode = provider.darkroomMode;
    final isHandsFree = provider.isHandsFreeActive;

    return SafeArea(
      top: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.only(
              left: 12.0,
              right: 12.0,
              top: 12.0,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 12.0 : 20.0,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF060B1E).withOpacity(0.4),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live Listening Animation Banner
                if (isListening || isDictating || isCallActive || isHandsFree) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10.0),
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: isDictating
                          ? const Color(0xFF8B5CF6).withOpacity(0.15)
                          : (isCallActive || isHandsFree)
                          ? const Color(0xFFC5A059).withOpacity(0.15)
                          : const Color(0xFF0EA5E9).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDictating
                            ? const Color(0xFF8B5CF6).withOpacity(0.4)
                            : (isCallActive || isHandsFree)
                            ? const Color(0xFFC5A059).withOpacity(0.4)
                            : const Color(0xFF0EA5E9).withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WaveIndicator(
                          color: isDictating
                              ? const Color(0xFF8B5CF6)
                              : (isCallActive || isHandsFree)
                              ? const Color(0xFFC5A059)
                              : const Color(0xFF0EA5E9),
                          count: 6,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDictating
                              ? '🎙️ جاري الاستماع للإملاء الصوتي... تحدث الآن'
                              : (isCallActive || isHandsFree)
                              ? '📞 الحوار الصوتي مستمر... تحدث وسيجيبك المساعد الأكاديمي'
                              : '🎙️ جاري الاستماع...',
                          style: TextStyle(
                            color: isDictating
                                ? const Color(0xFFA78BFA)
                                : (isCallActive || isHandsFree)
                                ? const Color(0xFFE5C158)
                                : const Color(0xFF38BDF8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Upper row: Voice & Smart Controls (capsules)
                if (!isCallActive) ...[
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildActionCapsule(
                        label: 'Hi Ray',
                        icon: darkroomMode ? Icons.graphic_eq : Icons.auto_awesome,
                        color: const Color(0xFFC5A059),
                        isActive: darkroomMode,
                        enabled: !provider.isLoading,
                        onTap: () => provider.toggleDarkroomMode(),
                      ),
                      _buildActionCapsule(
                        label: 'مساعد صوتي',
                        icon: Icons.record_voice_over_outlined,
                        color: const Color(0xFF8B5CF6),
                        isActive: false,
                        enabled: !provider.isLoading,
                        onTap: () => VoiceAssistantModal.show(context),
                      ),
                      _buildActionCapsule(
                        label: 'مكالمة',
                        icon: Icons.phone_in_talk_outlined,
                        color: const Color(0xFF10B981),
                        isActive: false,
                        enabled: !provider.isLoading,
                        onTap: () => provider.startCall(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Main Row: Attachment, Expanded TextField, Mic Button, Send Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 1. Attachments Button
                    IconButton(
                      onPressed: provider.isLoading
                          ? null
                          : () {
                              setState(() {
                                _showGlassMenu = !_showGlassMenu;
                              });
                            },
                      icon: Icon(
                        _showGlassMenu ? Icons.close : Icons.attach_file,
                        color: _showGlassMenu
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _showGlassMenu || hasAttachment
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          side: _showGlassMenu || hasAttachment
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                )
                              : BorderSide(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                                ),
                        ),
                        minimumSize: const Size(44, 44),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 2. Input TextField (minLines: 1, maxLines: 6)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDictating
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(14.0),
                          border: Border.all(
                            color: isDictating
                                ? Theme.of(context).colorScheme.secondary.withOpacity(0.5)
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                          ),
                        ),
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          maxLines: 6,
                          minLines: 1,
                          enabled: !isCallActive,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14.0,
                            fontFamily: 'Cairo',
                          ),
                          decoration: InputDecoration(
                            hintText: isCallActive
                                ? 'وضع المكالمة نشط...'
                                : isDictating
                                ? '🎙️ تحدث الآن للإملاء الصوتي...'
                                : provider.selectedAttachments.any((a) => a.type == 'pdf')
                                ? 'اكتب سؤالك عن الملف...'
                                : provider.selectedAttachments.any((a) => a.type == 'image')
                                ? 'اكتب سؤالك عن الصورة...'
                                : 'اكتب سؤالك هنا...',
                            hintStyle: TextStyle(
                              color: isDictating
                                  ? Theme.of(context).colorScheme.secondary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 13.0,
                              fontFamily: 'Cairo',
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14.0,
                              vertical: 16.0,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 3. Explicit speech-to-text dictation toggle
                    IconButton(
                      onPressed: provider.isLoading
                          ? null
                          : () async {
                              if (isDictating) {
                                await provider.stopDictation();
                              } else {
                                await provider.startDictation();
                              }
                            },
                      tooltip: isDictating ? 'إيقاف الإملاء الصوتي' : 'إملاء صوتي',
                      icon: Icon(
                        isDictating ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                        color: isDictating
                            ? Theme.of(context).colorScheme.onError
                            : Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: isDictating
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.surfaceContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                        minimumSize: const Size(44, 44),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 4. Send Message Button / Stop Answer Button / Call End Button
                    isCallActive
                        ? IconButton(
                            onPressed: () => provider.hangUp(),
                            icon: Icon(
                              Icons.call_end,
                              color: Theme.of(context).colorScheme.onError,
                              size: 20,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.error,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              minimumSize: const Size(44, 44),
                            ),
                          )
                        : provider.isLoading
                        ? IconButton(
                            onPressed: () => provider.stopGenerating(),
                            icon: Icon(
                              Icons.stop,
                              color: Theme.of(context).colorScheme.onError,
                              size: 20,
                            ),
                            tooltip: 'إيقاف الإجابة',
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.error,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              minimumSize: const Size(44, 44),
                            ),
                          )
                        : IconButton(
                            onPressed:
                                (_textController.text.trim().isEmpty && !hasAttachment) ||
                                    provider.isLoading ||
                                    isCallActive
                                ? null
                                : () {
                                    provider.sendMessage(_textController.text);
                                    _textController.clear();
                                    if (isDictating) {
                                      provider.stopDictation();
                                    }
                                  },
                            icon: Icon(
                              Icons.send,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: 18,
                            ),
                            style: IconButton.styleFrom(
                              disabledBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.05),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              minimumSize: const Size(44, 44),
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 10),

                // Bottom design credit and warnings
                Column(
                  children: [
                    Text(
                      'قد ينتج الذكاء الاصطناعي أحياناً إجابات غير دقيقة.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 9.0,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تصميم: محمد جبار إبراهيم  |  إشراف: رئاسة قسم تقنيات الأشعة والسونار',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        fontSize: 9.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCapsule({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isActive
                ? color.withOpacity(0.15)
                : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConsultantRoomsSheet(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        final List<Map<String, dynamic>> rooms = [
          {
            'name': 'غرفة الأشعة التقليدية',
            'icon': Icons.settings_system_daydream,
            'color': const Color(0xFF0EA5E9),
          },
          {
            'name': 'غرفة المفراس الحلزوني',
            'icon': Icons.biotech,
            'color': const Color(0xFF10B981),
          },
          {
            'name': 'غرفة الرنين المغناطيسي',
            'icon': Icons.fluorescent,
            'color': const Color(0xFF8B5CF6),
          },
          {
            'name': 'غرفة هشاشة العظام',
            'icon': Icons.accessibility_new,
            'color': const Color(0xFFF59E0B),
          },
          {'name': 'غرفة أشعة الثدي', 'icon': Icons.bubble_chart, 'color': const Color(0xFFD946EF)},
          {
            'name': 'غرفة أشعة الأسنان',
            'icon': Icons.border_clear,
            'color': const Color(0xFFEAB308),
          },
        ];

        return Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اختر غرفة أكاديمية متخصصة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'يركّز المساعد التعليمي على موضوع هذا التخصص الإشعاعي',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final crossAxisCount = width > 500 ? 3 : 2;
                    final childAspectRatio = width > 500 ? 1.5 : 1.3;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: rooms.length,
                      itemBuilder: (context, index) {
                        final room = rooms[index];
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            provider.selectConsultantRoom(room['name']);
                          },
                          borderRadius: BorderRadius.circular(16.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(room['icon'], color: room['color'], size: 28),
                                const SizedBox(height: 10),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    room['name'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Active call screen floating status
  Widget _buildCallOverlay(ChatProvider provider) {
    final isListen = provider.isListening;
    final isSpeak = provider.isSpeaking;

    return Positioned(
      top: 16.0,
      left: 16.0,
      right: 16.0,
      child: Center(
        child: GestureDetector(
          onTap: isSpeak ? () => provider.stopSpeakingMessage() : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: isSpeak
                  ? const Color(0xFF1E3A8A).withOpacity(0.95) // Dark blue when speaking
                  : const Color(0xFF14532D).withOpacity(0.95), // Dark green when listening/active
              borderRadius: BorderRadius.circular(30.0),
              border: Border.all(
                color: isSpeak
                    ? const Color(0xFF3B82F6).withOpacity(0.5)
                    : const Color(0xFF16A34A).withOpacity(0.5),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10.0)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wave animation status
                if (isListen)
                  const WaveIndicator(color: Color(0xFFC5A059))
                else if (isSpeak)
                  const Icon(Icons.volume_up, color: Color(0xFFC5A059), size: 16)
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC5A059),
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 10),
                Text(
                  isSpeak
                      ? 'المساعد يتحدث... (انقر للمقاطعة)'
                      : provider.isLoading
                      ? 'المساعد يفكر...'
                      : 'جارٍ الاستماع...',
                  style: TextStyle(
                    color: isSpeak ? const Color(0xFFDBEAFE) : const Color(0xFFBBF7D0),
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Darkroom wake word standby status
  // Apple Standard VisionOS / iOS Dynamic HUD Interface for Darkroom Mode
  Widget _buildDarkroomStandby(ChatProvider provider) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            color: const Color(0xFF020617).withOpacity(0.90),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  // Techy Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC5A059).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.3), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFFC5A059), size: 18),
                        SizedBox(width: 10),
                        Text(
                          'نظام مساعد النخبة الذكي',
                          style: TextStyle(
                            color: Color(0xFFF1F5F9),
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Futuristic HUD Core
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer rotating ring (simulated by dashed border or just multiple rings)
                        Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFC5A059).withOpacity(0.2),
                              width: 1.0,
                            ),
                          ),
                        ),
                        // Pulsing Core Ring
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                const Color(0xFFC5A059).withOpacity(0.1),
                                const Color(0xFFC5A059).withOpacity(0.6),
                                const Color(0xFFC5A059).withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF020617),
                              ),
                            ),
                          ),
                        ),
                        // Inner Glowing Core
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0F172A),
                            border: Border.all(color: const Color(0xFFC5A059), width: 2.0),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFC5A059).withOpacity(0.5),
                                blurRadius: 25,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFFC5A059), size: 60),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    'أنا أستمع...',
                    style: TextStyle(
                      color: Color(0xFFC5A059),
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'تحدث الآن لتوجيه الأوامر أو طرح الأسئلة',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14.0, fontFamily: 'Cairo'),
                  ),

                  if (provider.wakeTranscript.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC5A059).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.3)),
                      ),
                      child: Text(
                        '🎙 ${provider.wakeTranscript}',
                        style: const TextStyle(
                          color: Color(0xFFF1F5F9),
                          fontSize: 14.0,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Exit Button
                  Padding(
                    padding: const EdgeInsets.only(bottom: 30.0),
                    child: OutlinedButton.icon(
                      onPressed: () => provider.toggleDarkroomMode(),
                      icon: const Icon(Icons.close, color: Color(0xFFF1F5F9), size: 20),
                      label: const Text(
                        'إغلاق المساعد',
                        style: TextStyle(
                          color: Color(0xFFF1F5F9),
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
                        backgroundColor: Colors.white.withOpacity(0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassmorphicMenu(ChatProvider provider) {
    return Positioned(
      bottom: 85.0,
      right: 16.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22.0),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 270,
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.6),
              borderRadius: BorderRadius.circular(22.0),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16.0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'المرفقات',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildMenuItem(
                  title: 'تسجيل صوتي',
                  subtitle: 'سجل محاضرة أو سؤالاً',
                  icon: Icons.auto_awesome,
                  color: const Color(0xFF8B5CF6),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecordingScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  title: 'ملف أكاديمي PDF',
                  subtitle: 'اختر ملف PDF حتى 12 MB',
                  icon: Icons.description,
                  color: const Color(0xFF0EA5E9),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _pickPdf(provider);
                  },
                ),
                _buildMenuItem(
                  title: 'صور الأشعة والنماذج',
                  subtitle: 'اختر صورة من المعرض للتحليل',
                  icon: Icons.image,
                  color: const Color(0xFFF59E0B),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _pickImage(ImageSource.gallery, provider);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0),
                  child: Divider(color: Color(0xFF1E293B), height: 16, thickness: 1),
                ),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '⚡ أدوات النخبة Pro',
                    style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildMenuItem(
                  title: 'الرؤية الحية',
                  subtitle: 'لقطات كاميرا اختيارية للتحليل التعليمي',
                  icon: Icons.videocam,
                  color: const Color(0xFF10B981),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LiveVisionScreen()),
                    );
                  },
                ),
                _buildMenuItem(
                  title: 'الغرف الأكاديمية',
                  subtitle: '6 مساحات تعليمية متخصصة',
                  icon: Icons.people,
                  color: const Color(0xFFD97706),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _showConsultantRoomsSheet(context, provider);
                  },
                ),
                _buildMenuItem(
                  title: 'فيديو تعليمي من يوتيوب',
                  subtitle: 'ابحث عن فيديو توضيحي لأي مرض أو حالة',
                  icon: Icons.play_circle_fill,
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _textController.text = 'اريد فيديو يوتيوب يوضح موضوع: ';
                    _focusNode.requestFocus();
                  },
                ),
                _buildMenuItem(
                  title: 'المترجم الطبي',
                  subtitle: 'ترجمة وشرح نطق المصطلحات الطبية',
                  icon: Icons.text_fields,
                  color: const Color(0xFFEAB308),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _textController.text = 'كيف أنطق وأترجم المصطلح الطبي: ';
                    _focusNode.requestFocus();
                  },
                ),
                _buildMenuItem(
                  title: 'قراءة الروابط الذكية',
                  subtitle: 'أدخل رابطاً لتلخيص محتواه',
                  icon: Icons.link,
                  color: const Color(0xFF0EA5E9),
                  onTap: () {
                    setState(() => _showGlassMenu = false);
                    _textController.text = 'لخص محتوى الرابط التالي: ';
                    _focusNode.requestFocus();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9.5,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.3), width: 1),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showMedicalDisclaimer(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F1E32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.health_and_safety, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text(
                'تنويه وإخلاء مسؤولية طبي',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تطبيق (مساعد نخبة الأشعة) منصة محاكاة تعليمية وأكاديمية مخصصة لطلاب وفنيي جامعة النخبة - قسم تقنيات الأشعة والسونار.\n',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                Text(
                  '• جميع الإجابات والتقارير والتحليلات المولدة بواسطة المساعد الذكي هي لغرض التدريب والدراسة الأكاديمية فقط.\n'
                  '• لا يُعتبر هذا التطبيق بديلاً عن التشخيص الطبي السريري أو الاستشارة الطبيّة من طبيب مختص.\n'
                  '• يجب التأكد دائماً من القرارات السريرية عبر المراجع الطبية المعتمدة والأطباء الاستشاريين.',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5A059),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'موافق وفهمت',
                style: TextStyle(
                  color: Colors.black,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
