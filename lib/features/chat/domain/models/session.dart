import 'package:uuid/uuid.dart';
import 'chat_message.dart';

class Session {
  final String id;
  final String name;
  final String characterId; // Main character (or first in group)
  final List<String> groupCharacterIds; // For group chats
  final List<String> worldInfoIds; // For session-specific world info
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  Session({
    required this.id,
    required this.name,
    this.characterId = '',
    this.groupCharacterIds = const [],
    this.worldInfoIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  bool get isGroup => groupCharacterIds.isNotEmpty;

  Session copyWith({
    String? name,
    String? characterId,
    List<String>? groupCharacterIds,
    List<String>? worldInfoIds,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) {
    return Session(
      id: id,
      name: name ?? this.name,
      characterId: characterId ?? this.characterId,
      groupCharacterIds: groupCharacterIds ?? this.groupCharacterIds,
      worldInfoIds: worldInfoIds ?? this.worldInfoIds,
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
      'groupCharacterIds': groupCharacterIds,
      'worldInfoIds': worldInfoIds,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse DateTime
    DateTime parseDate(dynamic value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return Session(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? 'New Chat',
      characterId: json['characterId']?.toString() ?? '',
      groupCharacterIds: (json['groupCharacterIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      worldInfoIds: (json['worldInfoIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      messages: (json['messages'] as List?)
          ?.map((m) {
            try {
              if (m is Map) {
                return ChatMessage.fromJson(Map<String, dynamic>.from(m));
              }
              return null;
            } catch (e) {
              print('Error parsing message: $e');
              return null;
            }
          })
          .whereType<ChatMessage>()
          .toList() ?? [],
    );
  }
}
