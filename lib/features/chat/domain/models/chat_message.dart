class ChatMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;
  // Branching support
  final List<String> swipes; // Alternative contents for this message node
  final int currentIndex; // Currently selected index in swipes
  final Map<String, dynamic>? metadata; // Extra info like prompt, token usage, etc.

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.swipes = const [],
    this.currentIndex = 0,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'swipes': swipes,
      'currentIndex': currentIndex,
      'metadata': metadata,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final content = json['content']?.toString() ?? '';
    final swipesRaw = json['swipes'];
    List<String> swipes = [];
    if (swipesRaw != null && swipesRaw is List) {
      swipes = swipesRaw.map((e) => e.toString()).toList();
    }
    // If swipes is empty but content exists, initialize swipes with content
    if (swipes.isEmpty && content.isNotEmpty) {
      swipes = [content];
    }

    DateTime parseDate(dynamic value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    return ChatMessage(
      role: json['role']?.toString() ?? 'user',
      content: content,
      timestamp: parseDate(json['timestamp']),
      swipes: swipes,
      currentIndex: (json['currentIndex'] is int) ? json['currentIndex'] : 0,
      metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata']) : null,
    );
  }

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    List<String>? swipes,
    int? currentIndex,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      swipes: swipes ?? this.swipes,
      currentIndex: currentIndex ?? this.currentIndex,
      metadata: metadata ?? this.metadata,
    );
  }
}
