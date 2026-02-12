class ChatMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;
  // Branching support
  final List<String> swipes; // Alternative contents for this message node
  final int currentIndex; // Currently selected index in swipes

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.swipes = const [],
    this.currentIndex = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'swipes': swipes,
      'currentIndex': currentIndex,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final content = json['content'] ?? '';
    final swipesRaw = json['swipes'];
    List<String> swipes = [];
    if (swipesRaw != null && swipesRaw is List) {
      swipes = List<String>.from(swipesRaw);
    }
    // If swipes is empty but content exists, initialize swipes with content
    if (swipes.isEmpty && content.isNotEmpty) {
      swipes = [content];
    }

    return ChatMessage(
      role: json['role'] ?? 'user',
      content: content,
      timestamp: json['timestamp'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp']) 
          : DateTime.now(),
      swipes: swipes,
      currentIndex: json['currentIndex'] ?? 0,
    );
  }

  ChatMessage copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    List<String>? swipes,
    int? currentIndex,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      swipes: swipes ?? this.swipes,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }
}
