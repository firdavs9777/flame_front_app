import 'package:flame/core/navigation/app_routes.dart';

/// What a push notification is about.
///
/// The names mirror the `type` the backend sends verbatim
/// (`flame/services/pushService.js`), so a new server-side type shows up here
/// as [PushType.unknown] rather than as a crash.
enum PushType { chatMessage, newMatch, promotion, reengagement, unknown }

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
    this.route,
  });

  final PushType type;
  final String? conversationId;
  final String? matchId;

  /// Where a campaign wants to land, as an [AppRoutes] name.
  ///
  /// Author-supplied, so it is never trusted: [destination] only honours a
  /// value that is actually in [AppRoutes.all]. A campaign written against a
  /// route that a later release renames or removes must open the app, not
  /// strand the user on a not-found screen they did not ask for.
  final String? route;

  /// Parses an FCM `data` map. Never throws: a malformed or unrecognised
  /// payload becomes [PushType.unknown] with no ids, which resolves to no
  /// destination and so opens the app without navigating.
  factory PushPayload.fromData(Map<String, dynamic>? data) {
    if (data == null) return const PushPayload(type: PushType.unknown);

    return PushPayload(
      type: _typeFrom(data['type']),
      conversationId: _idFrom(data['conversationId']),
      matchId: _idFrom(data['matchId']),
      route: _idFrom(data['route']),
    );
  }

  static PushType _typeFrom(Object? raw) {
    switch (raw) {
      case 'chat_message':
        return PushType.chatMessage;
      case 'new_match':
        return PushType.newMatch;
      case 'promotion':
        return PushType.promotion;
      case 'reengagement':
        return PushType.reengagement;
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
      case PushType.promotion:
        // Only a route the router actually knows. An unknown one opens the
        // app, which is a campaign that under-delivers rather than a dead end.
        final target = route;
        if (target == null || !AppRoutes.all.contains(target)) return null;
        // Routes needing typed arguments cannot be reached from a payload that
        // carries none -- they would land on RouteNotFoundScreen. Only
        // argument-free destinations are honoured.
        if (_needsArguments.contains(target)) return null;
        return PushDestination(target, null);

      case PushType.reengagement:
        // Nothing specific: the point is to open Flame at all.
        return null;

      case PushType.unknown:
        return null;
    }
  }
}

/// Routes whose screens require typed arguments, so a campaign cannot name
/// them. Kept beside the parser rather than in AppRoutes because this is a
/// fact about what a PAYLOAD can express, not about the route table.
const _needsArguments = <String>{
  AppRoutes.chat,
  AppRoutes.profileDetail,
  AppRoutes.mediaViewer,
  AppRoutes.storyViewer,
};

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
