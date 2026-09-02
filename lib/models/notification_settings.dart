/// User notification preferences, backed by `/notifications/settings`.
///
/// Two channels, not one, and two categories that exist on both.
///
/// PUSH: [enabled] (the master switch), [chatMessages], [matches],
/// [promotionsPush] and [reengagementPush].
/// EMAIL: [promotions] and [reengagement]. Nothing about the push master
/// switch may govern those — a push toggle silently stopping someone's email
/// would be wrong.
///
/// Promotions and reminders appear in both lists on purpose. One flag spanning
/// both channels could not express "email me about offers but do not interrupt
/// my phone", which is the arrangement most people actually want, and reusing
/// the email flag for push would enrol every email subscriber into a channel
/// they never agreed to.
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

  /// Marketing, on push. Opt-IN and defaulted false for the same reason
  /// [promotions] is — and separately from it, because consenting to marketing
  /// email is not consenting to a marketing notification.
  final bool promotionsPush;

  /// The re-engagement ladder, on push. Opt-OUT, mirroring [reengagement]:
  /// it concerns the account's own state rather than promotion.
  final bool reengagementPush;

  const NotificationSettings({
    required this.enabled,
    required this.chatMessages,
    required this.matches,
    this.promotions = false,
    this.reengagement = true,
    this.promotionsPush = false,
    this.reengagementPush = true,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      enabled: json['enabled'] ?? true,
      chatMessages: json['chat_messages'] ?? true,
      matches: json['matches'] ?? true,
      promotions: json['promotions'] ?? false,
      reengagement: json['reengagement'] ?? true,
      promotionsPush: json['promotions_push'] ?? false,
      reengagementPush: json['reengagement_push'] ?? true,
    );
  }

  NotificationSettings copyWith({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
    bool? promotionsPush,
    bool? reengagementPush,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      chatMessages: chatMessages ?? this.chatMessages,
      matches: matches ?? this.matches,
      promotions: promotions ?? this.promotions,
      reengagement: reengagement ?? this.reengagement,
      promotionsPush: promotionsPush ?? this.promotionsPush,
      reengagementPush: reengagementPush ?? this.reengagementPush,
    );
  }

  /// Builds a camelCase PUT body containing only the provided fields.
  static Map<String, dynamic> toPutBody({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
    bool? promotionsPush,
    bool? reengagementPush,
  }) {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (chatMessages != null) body['chatMessages'] = chatMessages;
    if (matches != null) body['matches'] = matches;
    if (promotions != null) body['promotions'] = promotions;
    if (reengagement != null) body['reengagement'] = reengagement;
    if (promotionsPush != null) body['promotionsPush'] = promotionsPush;
    if (reengagementPush != null) body['reengagementPush'] = reengagementPush;
    return body;
  }
}
