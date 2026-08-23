/// User notification preferences, backed by `/notifications/settings`.
///
/// Two channels, not one. [enabled], [chatMessages] and [matches] are PUSH;
/// [promotions] and [reengagement] are EMAIL, and nothing about the push master
/// switch may govern them — a push toggle silently stopping someone's email
/// would be wrong.
///
/// The GET/PUT response body is snake_case (`chat_messages`, `matches`), but
/// the PUT request body the backend expects is camelCase (`chatMessages`,
/// `matches`). [fromJson] parses the former; [toPutBody] emits the latter.
class NotificationSettings {
  final bool enabled;
  final bool chatMessages;
  final bool matches;

  /// Marketing. Opt-IN — defaults false, and the server will not send until a
  /// user turns it on here.
  final bool promotions;

  /// The re-engagement ladder. Opt-OUT, because it is about the account's own
  /// state rather than promotion.
  final bool reengagement;

  const NotificationSettings({
    required this.enabled,
    required this.chatMessages,
    required this.matches,
    this.promotions = false,
    this.reengagement = true,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      enabled: json['enabled'] ?? true,
      chatMessages: json['chat_messages'] ?? true,
      matches: json['matches'] ?? true,
      promotions: json['promotions'] ?? false,
      reengagement: json['reengagement'] ?? true,
    );
  }

  NotificationSettings copyWith({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      chatMessages: chatMessages ?? this.chatMessages,
      matches: matches ?? this.matches,
      promotions: promotions ?? this.promotions,
      reengagement: reengagement ?? this.reengagement,
    );
  }

  /// Builds a camelCase PUT body containing only the provided fields.
  static Map<String, dynamic> toPutBody({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
  }) {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (chatMessages != null) body['chatMessages'] = chatMessages;
    if (matches != null) body['matches'] = matches;
    if (promotions != null) body['promotions'] = promotions;
    if (reengagement != null) body['reengagement'] = reengagement;
    return body;
  }
}
