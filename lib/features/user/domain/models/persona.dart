import 'package:uuid/uuid.dart';

class Persona {
  final String id;
  final String name;
  final String description; // Personality description
  final String avatarPath;

  Persona({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarPath = '',
  });

  factory Persona.createDefault() {
    return Persona(
      id: const Uuid().v4(),
      name: 'User',
      description: 'A mysterious user.',
      avatarPath: '',
    );
  }

  Persona copyWith({
    String? name,
    String? description,
    String? avatarPath,
  }) {
    return Persona(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatarPath': avatarPath,
    };
  }

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'] ?? const Uuid().v4(),
      name: json['name'] ?? 'User',
      description: json['description'] ?? '',
      avatarPath: json['avatarPath'] ?? '',
    );
  }
}
