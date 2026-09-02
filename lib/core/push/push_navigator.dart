import 'package:flutter/widgets.dart';

import 'package:flame/core/push/push_payload.dart';

/// Navigates in response to a notification tap.
///
/// A push handler runs with no `BuildContext` — it is called by the plugin, not
/// by a widget — so it navigates through the app's [GlobalKey] instead. The key
/// is passed in rather than reached for globally so this can be tested against
/// a throwaway navigator.
class PushNavigator {
  const PushNavigator(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  /// Routes to [payload]'s destination.
  ///
  /// Returns whether it navigated. False is a normal outcome, not an error:
  /// an unrecognised type, a match with no conversation yet, or a tap that
  /// arrived before the navigator was mounted all mean "just open the app",
  /// which is what happens when nothing is pushed.
  bool go(PushPayload payload) {
    final destination = payload.destination;
    if (destination == null) return false;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return false;

    navigator.pushNamed(
      destination.routeName,
      arguments: destination.arguments,
    );
    return true;
  }
}
