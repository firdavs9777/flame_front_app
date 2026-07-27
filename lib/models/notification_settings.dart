/// User notification preferences, backed by `/notifications/settings`.
///
/// The GET/PUT response body is snake_case (`chat_messages`, `matches`), but
/// the PUT request body the backend expects is camelCase (`chatMessages`,
/// `matches`). [fromJson] parses the former; [toPutBody] emits the latter.
class NotificationSettings {
  final bool enabled;
  final bool chatMessages;
  final bool matches;

  const NotificationSettings({
    required this.enabled,
    required this.chatMessages,
    required this.matches,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      enabled: json['enabled'] ?? true,
      chatMessages: json['chat_messages'] ?? true,
      matches: json['matches'] ?? true,
    );
  }

  NotificationSettings copyWith({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      chatMessages: chatMessages ?? this.chatMessages,
      matches: matches ?? this.matches,
    );
  }

  /// Builds a camelCase PUT body containing only the provided fields.
  static Map<String, dynamic> toPutBody({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
  }) {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (chatMessages != null) body['chatMessages'] = chatMessages;
    if (matches != null) body['matches'] = matches;
    return body;
  }
}
