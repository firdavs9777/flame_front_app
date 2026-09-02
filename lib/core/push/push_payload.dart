import 'package:flame/core/navigation/app_routes.dart';

/// What a push notification is about.
///
/// The names mirror the `type` the backend sends verbatim
/// (`flame/services/pushService.js`), so a new server-side type shows up here
/// as [PushType.unknown] rather than as a crash.
enum PushType { chatMessage, newMatch, unknown }

/// A push notification's `data` map, parsed into something typed.
///
/// Two things about the wire format drive every decision here:
///
/// 1. **Every value is a string.** The server runs `sanitizeData()` over the
///    map, which calls `String(value)` on everything, because FCM rejects a
///    `data` payload containing anything else.
/// 2. **Absent ids arrive as `''`, not as a missing key.** `chatPushPayload`
///    writes `conversationId: conversationId ? String(conversationId) : ''`.
///    So "missing" and "empty" mean the same thing, and both become `null`
///    here — otherwise every caller would have to remember to check for an
///    empty string, and the one that forgot would navigate to a chat whose id
///    is the empty string.
class PushPayload {
  const PushPayload({
    required this.type,
    this.conversationId,
    this.matchId,
  });

  final PushType type;
  final String? conversationId;
  final String? matchId;

  /// Parses an FCM `data` map. Never throws: a malformed or unrecognised
  /// payload becomes [PushType.unknown] with no ids, which resolves to no
  /// destination and so opens the app without navigating.
  factory PushPayload.fromData(Map<String, dynamic>? data) {
    if (data == null) return const PushPayload(type: PushType.unknown);

    return PushPayload(
      type: _typeFrom(data['type']),
      conversationId: _idFrom(data['conversationId']),
      matchId: _idFrom(data['matchId']),
    );
  }

  static PushType _typeFrom(Object? raw) {
    switch (raw) {
      case 'chat_message':
        return PushType.chatMessage;
      case 'new_match':
        return PushType.newMatch;
      default:
        return PushType.unknown;
    }
  }

  /// Empty is absent — see the class doc.
  static String? _idFrom(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  /// Where tapping this notification should land, or null to just open the app.
  ///
  /// Both types resolve to the conversation, because that is what the person
  /// tapping wants in either case: a message is read in its thread, and a new
  /// match is acted on by saying something. A match whose payload carries no
  /// conversation id — which the server can emit, since it writes `''` when the
  /// match has no conversation yet — has nowhere better to go than the app
  /// itself, so it navigates nowhere rather than guessing.
  PushDestination? get destination {
    switch (type) {
      case PushType.chatMessage:
      case PushType.newMatch:
        final id = conversationId;
        if (id == null) return null;
        return PushDestination(AppRoutes.chat, ChatRouteArgs.id(id));
      case PushType.unknown:
        return null;
    }
  }
}

/// A route name and its arguments, ready for `Navigator.pushNamed`.
///
/// Separate from the navigation itself so the decision of *where a payload
/// goes* can be tested without a widget tree, a navigator, or Firebase.
class PushDestination {
  const PushDestination(this.routeName, this.arguments);

  final String routeName;
  final Object? arguments;

  @override
  bool operator ==(Object other) =>
      other is PushDestination &&
      other.routeName == routeName &&
      _sameArgs(other.arguments, arguments);

  /// [ChatRouteArgs] has no value equality of its own, so compare the parts
  /// that identify a destination. Anything else falls back to identity.
  static bool _sameArgs(Object? a, Object? b) {
    if (a is ChatRouteArgs && b is ChatRouteArgs) {
      return a.id == b.id && identical(a.conversation, b.conversation);
    }
    return a == b;
  }

  @override
  int get hashCode => Object.hash(
        routeName,
        arguments is ChatRouteArgs ? (arguments as ChatRouteArgs).id : arguments,
      );

  @override
  String toString() => 'PushDestination($routeName)';
}
