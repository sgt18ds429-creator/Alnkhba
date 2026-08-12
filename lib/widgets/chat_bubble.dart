import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../services/file_export_helper.dart';

class ChatBubble extends StatelessWidget {
  final Message message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model Avatar (University Logo)
          if (!isUser) _buildAvatar(isUser, context),
          const SizedBox(width: 8.0),

          // Bubble Body
          Expanded(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 1. Attached items (images, PDFs, audios)
                if (message.attachments != null && message.attachments!.isNotEmpty)
                  _buildMessageAttachments(message.attachments!, context),

                // 2. Main Message Text bubble
                if (message.text.isNotEmpty) _buildTextBubble(isUser, context),

                // 3. Pronunciation card
                if (message.pronunciationAudio != null &&
                    message.pronunciationAudio != '__aud__' &&
                    message.pronunciationTerm != null)
                  _buildPronunciationCard(context, chatProvider),

                // 4. YouTube educational card
                if (message.youtubeQuery != null) _buildYoutubeCard(context),

                // 5. Clearly labelled AI-generated educational illustration
                if (message.generatedImage != null && message.generatedImage != '__gen__')
                  _buildGeneratedImage(
                    message.generatedImage!,
                    message.generatedImageMime,
                    context,
                  ),

                // 6. Reference image returned by Wikipedia
                if (message.wikiImageUrl != null)
                  _buildWikiImageUrl(message.wikiImageUrl!, context),
              ],
            ),
          ),

          const SizedBox(width: 8.0),
          // User Avatar
          if (isUser) _buildAvatar(isUser, context),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser, BuildContext context) {
    return Container(
      width: 32.0,
      height: 32.0,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: isUser
            ? null
            : Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5), width: 2),
      ),
      child: Center(
        child: isUser
            ? Icon(Icons.person, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18.0)
            : ClipOval(
                child: Image.asset(
                  'assets/logo_icon_v2.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) =>
                      Icon(Icons.school, color: Theme.of(context).colorScheme.primary, size: 16.0),
                ),
              ),
      ),
    );
  }

  Widget _buildUploadedImage(AttachmentItem attachment, BuildContext context) {
    try {
      final decodedBytes = attachment.bytes ?? base64Decode(attachment.base64);
      return Container(
        margin: const EdgeInsets.only(bottom: 6.0),
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.0),
          child: Image.memory(decodedBytes, fit: BoxFit.contain),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildPdfBadge(String pdfName, BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.primary, size: 18.0),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  pdfName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13.0,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageAttachments(List<AttachmentItem> attachments, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: attachments.map((a) {
        if (a.type == 'image') {
          return _buildUploadedImage(a, context);
        } else if (a.type == 'pdf') {
          return _buildPdfBadge(a.name, context);
        } else if (a.type == 'audio') {
          return _buildAudioBadge(a.name, context);
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _buildAudioBadge(String audioName, BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6.0),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Theme.of(context).colorScheme.secondary.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack, color: Theme.of(context).colorScheme.secondary, size: 18.0),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  audioName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 13.0,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextBubble(bool isUser, BuildContext context) {
    final borderRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(20.0),
            topRight: Radius.circular(4.0),
            bottomLeft: Radius.circular(20.0),
            bottomRight: Radius.circular(20.0),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4.0),
            topRight: Radius.circular(20.0),
            bottomLeft: Radius.circular(20.0),
            bottomRight: Radius.circular(20.0),
          );

    final bubbleWidget = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                : const Color(0xFF0F172A).withOpacity(0.6),
            borderRadius: borderRadius,
            border: Border.all(
              color: isUser
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
                  : const Color(0xFFC5A059).withOpacity(0.4),
              width: 1.2,
            ),
            boxShadow: isUser
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFC5A059).withOpacity(0.2),
                      blurRadius: 15.0,
                      spreadRadius: 1.0,
                    ),
                  ],
          ),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: _renderFormattedText(message.text, isUser, context),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubbleWidget,
        if (!isUser && message.text.isNotEmpty)
          Consumer<ChatProvider>(
            builder: (context, chatProvider, _) {
              final bool isSpeakingThis =
                  chatProvider.isSpeaking && chatProvider.currentlySpeakingMessageId == message.id;
              return Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: [
                    _buildExportButton(
                      context,
                      label: isSpeakingThis ? 'إيقاف' : 'استماع',
                      iconData: isSpeakingThis
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      color: isSpeakingThis
                          ? Theme.of(context).colorScheme.error
                          : const Color(0xFFF59E0B),
                      onTap: () {
                        chatProvider.speakMessageText(message.id, message.text);
                      },
                    ),
                    _buildExportButton(
                      context,
                      label: 'Word',
                      iconData: Icons.description_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      onTap: () {
                        _showSaveDialog(context, 'Word', (fileName) async {
                          final path = await FileExportHelper.exportToWord(fileName, message.text);
                          if (path != null && context.mounted) {
                            _showSaveSuccessSnackBar(context, path);
                          }
                        });
                      },
                    ),
                    _buildExportButton(
                      context,
                      label: 'PDF',
                      iconData: Icons.picture_as_pdf_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () {
                        _showSaveDialog(context, 'PDF', (fileName) async {
                          final path = await FileExportHelper.exportToPdf(fileName, message.text);
                          if (path != null && context.mounted) {
                            _showSaveSuccessSnackBar(context, path);
                          }
                        });
                      },
                    ),
                    _buildExportButton(
                      context,
                      label: 'نسخ',
                      iconData: Icons.copy_outlined,
                      color: Theme.of(context).colorScheme.tertiary,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'تم نسخ النص إلى الحافظة',
                              style: TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Theme.of(context).colorScheme.tertiary,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    _buildExportButton(
                      context,
                      label: 'إبلاغ',
                      iconData: Icons.flag_outlined,
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => _showReportDialog(context, chatProvider),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showReportDialog(BuildContext context, ChatProvider provider) async {
    const reasons = <MapEntry<String, String>>[
      MapEntry('محتوى طبي غير آمن', 'محتوى طبي غير آمن أو قد يسبب ضرراً'),
      MapEntry('محتوى مسيء أو كراهية', 'محتوى مسيء أو يحض على الكراهية'),
      MapEntry('خصوصية أو بيانات حساسة', 'يكشف بيانات شخصية أو حساسة'),
      MapEntry('معلومات خاطئة أو مضللة', 'معلومات خاطئة أو مضللة'),
      MapEntry('سبب آخر', 'سبب آخر'),
    ];
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('سبب الإبلاغ عن الإجابة'),
          children: reasons
              .map(
                (item) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, item.value),
                  child: Text(item.key),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (reason == null || !context.mounted) return;

    final reportError = await provider.reportMessage(
      messageId: message.id,
      messageText: message.text,
      reason: reason,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reportError ?? 'تم إرسال البلاغ للمراجعة. شكراً لمساعدتك في تحسين السلامة.'),
        backgroundColor: reportError == null
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSaveSuccessSnackBar(BuildContext context, String filePath) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حفظ المستند في الموقع الذي اخترته',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13.0,
            color: Theme.of(context).colorScheme.onInverseSurface,
          ),
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        action: SnackBarAction(
          label: 'فتح الملف',
          textColor: Theme.of(context).colorScheme.inversePrimary,
          onPressed: () async {
            try {
              await OpenFilex.open(filePath);
            } catch (_) {
              // Fail-safe
            }
          },
        ),
      ),
    );
  }

  void _showSaveDialog(
    BuildContext context,
    String fileType,
    Future<void> Function(String) onSave,
  ) {
    final TextEditingController nameController = TextEditingController(text: 'تقرير_أشعة_النخبة');

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            title: Text(
              'تسمية مستند $fileType',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أدخل اسماً ثم اختر مكان الحفظ من نافذة النظام:',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Cairo',
                    fontSize: 12.0,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'Cairo',
                    fontSize: 14.0,
                  ),
                  decoration: InputDecoration(
                    hintText: 'اسم الملف...',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    suffixText: fileType == 'PDF' ? '.pdf' : '.doc',
                    suffixStyle: TextStyle(color: Theme.of(context).colorScheme.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'إلغاء',
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(dialogContext);
                    unawaited(onSave(name));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'حفظ',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(nameController.dispose);
  }

  Widget _buildExportButton(
    BuildContext context, {
    required String label,
    required IconData iconData,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.3), width: 1.0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconData, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPronunciationCard(BuildContext context, ChatProvider provider) {
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Theme.of(context).colorScheme.tertiary.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              provider.playAudioBase64(message.pronunciationAudio!);
            },
            icon: Icon(
              Icons.play_circle_fill,
              color: Theme.of(context).colorScheme.tertiary,
              size: 36.0,
            ),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.pronunciationTerm!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  'اضغط للاستماع إلى النطق الإنجليزي الصحيح',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onTertiaryContainer.withOpacity(0.8),
                    fontSize: 11.0,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYoutubeCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      child: InkWell(
        onTap: () async {
          try {
            final query = message.youtubeQuery!;
            final url = Uri.parse(
              'https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}',
            );
            final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
            if (!opened) throw StateError('YouTube did not open');
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('تعذر فتح نتائج الفيديو حالياً.')));
            }
          }
        },
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.12),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 38.0,
                height: 38.0,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'شاهد على يوتيوب 🎬',
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      message.youtubeQuery!,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.0,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedImage(String base64Data, String? mime, BuildContext context) {
    try {
      final decodedBytes = base64Decode(base64Data);
      return Container(
        margin: const EdgeInsets.only(top: 8.0),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              blurRadius: 20.0,
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
              child: Image.memory(decodedBytes, fit: BoxFit.cover),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15.0)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 14.0,
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    'رسم تعليمي — مُنشأ بالذكاء الاصطناعي',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11.0,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildWikiImageUrl(String url, BuildContext context) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'upload.wikimedia.org' || uri.host.endsWith('.wikimedia.org'))) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 8.0),
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.3)),
        boxShadow: [BoxShadow(color: const Color(0xFFC5A059).withOpacity(0.15), blurRadius: 20.0)],
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15.0)),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 220,
                  color: Colors.black12,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'جارٍ تحميل الصورة المرجعية...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 11.5,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                height: 120,
                color: Colors.black26,
                padding: const EdgeInsets.all(12),
                child: const Center(
                  child: Text(
                    'تعذر تحميل الصورة المرجعية.',
                    style: TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontSize: 12.0),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15.0)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 14.0,
                ),
                const SizedBox(width: 6.0),
                Text(
                  'صورة مرجعية خارجية — Wikimedia',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 11.0,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parses simple markdown formatting: **bold**, *italic*, `code`
  Widget _renderFormattedText(String rawText, bool isUser, BuildContext context) {
    final List<TextSpan> spans = [];
    final regExp = RegExp(r'(\*\*.*?\*\*|\*.*?\*|`.*?`|[^\*`]+)');
    final matches = regExp.allMatches(rawText);

    for (final match in matches) {
      final matchText = match.group(0)!;

      if (matchText.length >= 4 && matchText.startsWith('**') && matchText.endsWith('**')) {
        spans.add(
          TextSpan(
            text: matchText.substring(2, matchText.length - 2),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (matchText.length >= 2 && matchText.startsWith('*') && matchText.endsWith('*')) {
        spans.add(
          TextSpan(
            text: matchText.substring(1, matchText.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (matchText.length >= 2 && matchText.startsWith('`') && matchText.endsWith('`')) {
        spans.add(
          TextSpan(
            text: matchText.substring(1, matchText.length - 1),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: isUser ? Colors.white12 : Colors.black26,
              color: isUser ? Colors.white : const Color(0xFFE5C158),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: matchText));
      }
    }

    return RichText(
      textDirection: TextDirection.rtl,
      text: TextSpan(
        style: TextStyle(
          color: isUser
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onSurface,
          fontSize: 14.0,
          height: 1.5,
          fontFamily: 'Cairo',
        ),
        children: spans,
      ),
    );
  }
}
