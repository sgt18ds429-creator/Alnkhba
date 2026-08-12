import 'dart:convert';
import 'dart:typed_data';

class AttachmentItem {
  final String base64;
  final String mime;
  final String name;
  final String type; // 'image', 'pdf', 'audio'
  String? text; // legacy cached metadata; never persisted in new sessions
  Uint8List? bytes; // cached binary bytes

  AttachmentItem({
    required this.base64,
    required this.mime,
    required this.name,
    required this.type,
    this.text,
    this.bytes,
  }) {
    if (bytes == null &&
        base64.isNotEmpty &&
        base64 != '__img__' &&
        base64 != '__pdf__' &&
        base64 != '__aud__') {
      try {
        bytes = base64Decode(base64);
      } catch (error) {
        // Invalid cached base64 should not prevent the message from loading.
        bytes = null;
      }
    }
  }

  factory AttachmentItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'image';
    final rawBase64 = json['base64'] as String? ?? '';
    final marker = type == 'image'
        ? '__img__'
        : type == 'pdf'
        ? '__pdf__'
        : '__aud__';
    // Old releases could persist full attachments. Cached history only needs
    // to show that an attachment existed, so never decode legacy file data at
    // startup.
    final safeBase64 = {'__img__', '__pdf__', '__aud__'}.contains(rawBase64) ? rawBase64 : marker;
    return AttachmentItem(
      base64: safeBase64,
      mime: json['mime'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: type,
      text: json['text'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'base64': base64,
      'mime': mime,
      'name': name,
      'type': type,
      if (text != null) 'text': text,
    };
  }

  AttachmentItem toSlim() {
    return AttachmentItem(
      base64: type == 'image'
          ? '__img__'
          : type == 'pdf'
          ? '__pdf__'
          : '__aud__',
      mime: mime,
      name: name,
      type: type,
      // Document content is never persisted in SharedPreferences.
      text: null,
    );
  }
}

class Message {
  final String id;
  final String role; // "user" or "model"
  final String text;
  final List<AttachmentItem>? attachments;
  final String? generatedImage;
  final String? generatedImageMime;
  final String? generatedImageUrl;
  final String? wikiImageUrl;
  final String? pronunciationAudio;
  final String? pronunciationTerm;
  final bool? quizMode;
  final String? youtubeQuery;

  Message({
    required this.id,
    required this.role,
    required this.text,
    this.attachments,
    this.generatedImage,
    this.generatedImageMime,
    this.generatedImageUrl,
    this.wikiImageUrl,
    this.pronunciationAudio,
    this.pronunciationTerm,
    this.quizMode,
    this.youtubeQuery,
  });

  // Create Message instance from JSON Map
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
      attachments: json['attachments'] is List
          ? (json['attachments'] as List)
                .whereType<Map<String, dynamic>>()
                .map(AttachmentItem.fromJson)
                .toList()
          : null,
      generatedImage: json['generatedImage'] as String?,
      generatedImageMime: json['generatedImageMime'] as String?,
      generatedImageUrl: json['generatedImageUrl'] as String?,
      wikiImageUrl: json['wikiImageUrl'] as String?,
      pronunciationAudio: json['pronunciationAudio'] as String?,
      pronunciationTerm: json['pronunciationTerm'] as String?,
      quizMode: json['quizMode'] as bool?,
      youtubeQuery: json['youtubeQuery'] as String?,
    );
  }

  // Convert Message instance to JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'text': text,
      if (attachments != null) 'attachments': attachments!.map((a) => a.toJson()).toList(),
      if (generatedImage != null) 'generatedImage': generatedImage,
      if (generatedImageMime != null) 'generatedImageMime': generatedImageMime,
      if (generatedImageUrl != null) 'generatedImageUrl': generatedImageUrl,
      if (wikiImageUrl != null) 'wikiImageUrl': wikiImageUrl,
      if (pronunciationAudio != null) 'pronunciationAudio': pronunciationAudio,
      if (pronunciationTerm != null) 'pronunciationTerm': pronunciationTerm,
      if (quizMode != null) 'quizMode': quizMode,
      if (youtubeQuery != null) 'youtubeQuery': youtubeQuery,
    };
  }

  // Create a copy of Message but strip heavy base64 strings to prevent storage bloat
  Message toSlim() {
    final slimText = text.length > 12000
        ? '${text.substring(0, 12000)}\n[تم اختصار الرسالة المحفوظة]'
        : text;
    return Message(
      id: id,
      role: role,
      text: slimText.replaceAll(RegExp(r'<img\b[^>]*>'), '[صورة]'),
      attachments: attachments?.map((a) => a.toSlim()).toList(),
      wikiImageUrl: wikiImageUrl,
      quizMode: quizMode,
      pronunciationTerm: pronunciationTerm,
      youtubeQuery: youtubeQuery,
      generatedImage: generatedImage != null ? '__gen__' : null,
      generatedImageUrl: generatedImageUrl != null ? '__gen__' : null,
      pronunciationAudio: pronunciationAudio != null ? '__aud__' : null,
    );
  }

  Message copyWith({
    String? id,
    String? role,
    String? text,
    List<AttachmentItem>? attachments,
    String? generatedImage,
    String? generatedImageMime,
    String? generatedImageUrl,
    String? wikiImageUrl,
    String? pronunciationAudio,
    String? pronunciationTerm,
    bool? quizMode,
    String? youtubeQuery,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
      generatedImage: generatedImage ?? this.generatedImage,
      generatedImageMime: generatedImageMime ?? this.generatedImageMime,
      generatedImageUrl: generatedImageUrl ?? this.generatedImageUrl,
      wikiImageUrl: wikiImageUrl ?? this.wikiImageUrl,
      pronunciationAudio: pronunciationAudio ?? this.pronunciationAudio,
      pronunciationTerm: pronunciationTerm ?? this.pronunciationTerm,
      quizMode: quizMode ?? this.quizMode,
      youtubeQuery: youtubeQuery ?? this.youtubeQuery,
    );
  }
}
