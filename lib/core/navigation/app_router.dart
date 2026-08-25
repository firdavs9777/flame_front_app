import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/navigation/chat_route_resolver.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/screens/auth/forgot_password_screen.dart';
import 'package:flame/screens/auth/login_screen.dart';
import 'package:flame/screens/chat/archived_conversations_screen.dart';
import 'package:flame/screens/chat/chat_search_screen.dart';
import 'package:flame/screens/chat/media_viewer_screen.dart';
import 'package:flame/screens/discover/discover_filters_screen.dart';
import 'package:flame/screens/profile/edit_profile/edit_profile_screen.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/screens/settings/blocked_users_screen.dart';
import 'package:flame/screens/settings/language_screen.dart';
import 'package:flame/screens/settings/notification_settings_screen.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/screens/stories/create_story_screen.dart';
import 'package:flame/screens/stories/story_viewer_screen.dart';

/// The navigator every push goes through.
///
/// Held here rather than inside a widget so a push-notification handler — which
/// runs with no BuildContext — has something to navigate with. Nothing consumes
/// it yet; it exists now because adding it later means editing main.dart again
/// in the middle of the notifications work.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Maps [AppRoutes] names to screens.
///
/// Every case reads its arguments through a checked cast helper, because
/// `RouteSettings.arguments` is an `Object?` that can hold anything: a stale
/// notification payload, a deep link typed by hand, a refactor that changed one
/// side. A wrong shape shows [RouteNotFoundScreen] rather than throwing.
abstract final class AppRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      case AppRoutes.discoverFilters:
        return _page(settings, const DiscoverFiltersScreen());

      case AppRoutes.settings:
        return _page(settings, const SettingsScreen());
      case AppRoutes.notificationSettings:
        return _page(settings, const NotificationSettingsScreen());
      case AppRoutes.language:
        return _page(settings, const LanguageScreen());
      case AppRoutes.blockedUsers:
        return _page(settings, const BlockedUsersScreen());

      case AppRoutes.editProfile:
        return _page(settings, const EditProfileScreen());

      case AppRoutes.profileDetail:
        return _typed<ProfileDetailArgs>(
          settings,
          args,
          (a) => ProfileDetailScreen(user: a.user, isPreview: a.isPreview),
        );

      case AppRoutes.chat:
        return _typed<ChatRouteArgs>(
          settings,
          args,
          (a) => ChatRouteResolver(args: a),
        );

      // The two closure-taking screens. Their dependencies are functions over
      // `ref`, not data, so the route builds them here instead of receiving
      // them — which also means the wiring is written once rather than at every
      // call site.
      case AppRoutes.chatSearch:
        return _page(
          settings,
          Consumer(
            builder: (context, ref, _) => ChatSearchScreen(
              search: (query, {int limit = 20, int offset = 0}) async {
                final result = await ref.read(chatServiceProvider).searchMessages(
                      query: query,
                      limit: limit,
                      offset: offset,
                    );
                if (!result.success) {
                  throw Exception(result.error ?? 'Search failed');
                }
                return result.data ?? [];
              },
            ),
          ),
        );

      case AppRoutes.archivedConversations:
        return _page(
          settings,
          Consumer(
            builder: (context, ref, _) => ArchivedConversationsScreen(
              load: () async {
                final result = await ref
                    .read(chatServiceProvider)
                    .getConversations(archived: true);
                if (!result.success) {
                  throw Exception(result.error ?? 'Could not load');
                }
                return result.data?.conversations ?? [];
              },
              unarchive: (id) =>
                  ref.read(conversationsProvider.notifier).unarchive(id),
            ),
          ),
        );

      case AppRoutes.mediaViewer:
        return _typed<MediaViewerArgs>(
          settings,
          args,
          (a) => MediaViewerScreen(url: a.url, heroTag: a.heroTag),
        );

      case AppRoutes.storyViewer:
        return _typed<StoryViewerArgs>(
          settings,
          args,
          (a) => StoryViewerScreen(
            users: a.users,
            initialUserIndex: a.initialUserIndex,
          ),
        );
      case AppRoutes.createStory:
        return _page(settings, const CreateStoryScreen());

      case AppRoutes.login:
        return _page(settings, const LoginScreen());

      case AppRoutes.forgotPassword:
        return _page(settings, const ForgotPasswordScreen());

      default:
        return _page(settings, const RouteNotFoundScreen());
    }
  }

  static MaterialPageRoute<dynamic> _page(RouteSettings settings, Widget child) =>
      MaterialPageRoute(settings: settings, builder: (_) => child);

  /// Builds [child] only when the arguments are the expected type. Anything else
  /// — wrong type, null, a bare String from a malformed link — lands on
  /// not-found, which is a screen the user can back out of rather than a crash.
  static MaterialPageRoute<dynamic> _typed<T>(
    RouteSettings settings,
    Object? args,
    Widget Function(T args) child,
  ) {
    if (args is! T) return _page(settings, const RouteNotFoundScreen());
    return _page(settings, child(args));
  }
}

/// Shown for a name with no case, or arguments of the wrong shape.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.routeNotFound,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
