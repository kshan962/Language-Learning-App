import 'dart:math';

class Message {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  Message({
    String? id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  })  : id = id ?? _generateId(),
        timestamp = timestamp ?? DateTime.now();

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? _generateId(),
      text: json['text'] ?? '',
      isUser: json['isUser'] ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  static String _generateId() {
    final random = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() +
        random.nextInt(10000).toString();
  }
}

class Conversation {
  final String id;
  final String title;
  final List<Message> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    String? id,
    required this.title,
    this.messages = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] ?? _generateId(),
      title: json['title'] ?? 'New Conversation',
      messages: json['messages'] != null
          ? List<Message>.from(json['messages'].map((m) => Message.fromJson(m)))
          : [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Conversation addMessage(Message message) {
    final newMessages = List<Message>.from(messages)..add(message);
    return Conversation(
      id: id,
      title: title,
      messages: newMessages,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static String _generateId() {
    final random = Random();
    return DateTime.now().millisecondsSinceEpoch.toString() +
        random.nextInt(10000).toString();
  }
}
