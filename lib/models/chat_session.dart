import 'message.dart';

class HistoryItem {
  final String role; // "user" or "model"
  final List<HistoryPart> parts;

  HistoryItem({required this.role, required this.parts});

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'];
    final partsList = rawParts is List ? rawParts : const [];
    return HistoryItem(
      role: json['role'] as String? ?? 'user',
      parts: partsList.whereType<Map<String, dynamic>>().map(HistoryPart.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'role': role, 'parts': parts.map((p) => p.toJson()).toList()};
  }
}

class HistoryPart {
  final String text;

  HistoryPart({required this.text});

  factory HistoryPart.fromJson(Map<String, dynamic> json) {
    return HistoryPart(text: json['text'] as String? ?? '');
  }

  Map<String, dynamic> toJson() {
    return {'text': text};
  }
}

class ChatSession {
  final String id;
  final String title;
  final int createdAt;
  final List<Message> messages;
  final List<HistoryItem> history;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.messages,
    required this.history,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final msgValue = json['messages'];
    final histValue = json['history'];
    final msgList = msgValue is List ? msgValue : const [];
    final histList = histValue is List ? histValue : const [];

    return ChatSession(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'محادثة',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      messages: msgList.whereType<Map<String, dynamic>>().map(Message.fromJson).toList(),
      history: histList.whereType<Map<String, dynamic>>().map(HistoryItem.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt,
      'messages': messages.map((m) => m.toJson()).toList(),
      'history': history.map((h) => h.toJson()).toList(),
    };
  }

  // Create a copy of the session but store slim messages to prevent storage bloat
  ChatSession toSlim() {
    return ChatSession(
      id: id,
      title: title.length > 50 ? title.substring(0, 50) : title,
      createdAt: createdAt,
      messages: messages
          .skip(messages.length > 80 ? messages.length - 80 : 0)
          .map((m) => m.toSlim())
          .toList(),
      history: history
          .skip(history.length > 40 ? history.length - 40 : 0)
          .map(
            (item) => HistoryItem(
              role: item.role,
              parts: item.parts
                  .map(
                    (part) => HistoryPart(
                      text: part.text.length > 6000 ? part.text.substring(0, 6000) : part.text,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }
}
