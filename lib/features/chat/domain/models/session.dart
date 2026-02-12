import 'package:uuid/uuid.dart';
import 'chat_message.dart';

class Session {
  final String id;
  final String name;
  final String characterId; // Currently unused in MVP but good for future
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  Session({
    required this.id,
    required this.name,
    this.characterId = '',
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  Session copyWith({
    String? name,
    String? characterId,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return Session(
      id: id,
      name: name ?? this.name,
      characterId: characterId ?? this.characterId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'characterId': characterId,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'New Chat',
      characterId: json['characterId'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch),
      messages: (json['messages'] as List?)
          ?.map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList() ?? [],
    );
  }
}
