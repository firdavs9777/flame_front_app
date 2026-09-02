import 'package:flutter/foundation.dart' show ValueChanged;

import 'package:flame/models/conversation.dart';
import 'package:flame/models/story.dart';
import 'package:flame/models/user.dart';

/// Every named destination in the app.
///
/// These exist so something OUTSIDE the widget tree can name a screen. A
/// destination that lives only as a closure inside a widget's `onTap` cannot be
/// reached by a push-notification handler, which has no context and no access to
/// that closure — it has a payload and a navigator key.
///
/// Paths are rooted and hierarchical rather than flat labels so they survive a
/// later move to URL-based routing (go_router) without renaming anything.
abstract final class AppRoutes {
  static const discoverFilters = '/discover/filters';

  static const settings = '/settings';
  static const notificationSettings = '/settings/notifications';
  static const language = '/settings/language';
  static const blockedUsers = '/settings/blocked';

  static const editProfile = '/profile/edit';
  static const profileDetail = '/profile/detail';

  static const chat = '/chat';
  static const chatSearch = '/chat/search';
  static const archivedConversations = '/chat/archived';

  static const mediaViewer = '/media';

  static const storyViewer = '/stories/view';
  static const createStory = '/stories/create';

  static const login = '/auth/login';
  static const forgotPassword = '/auth/forgot-password';

  static const languagePicker = '/languages/picker';

  /// Enumerated so the router's test can assert that every name resolves.
  /// A name added here without a matching case in [AppRouter] fails that test —
  /// which is the point: the alternative is discovering it from a dead tap.
  static const all = <String>[
    discoverFilters,
    settings,
    notificationSettings,
    language,
    blockedUsers,
    editProfile,
    profileDetail,
    chat,
    chatSearch,
    archivedConversations,
    mediaViewer,
    storyViewer,
    createStory,
    login,
    forgotPassword,
    languagePicker,
  ];
}

/// How a chat was reached.
///
/// Two constructors rather than one nullable pair, because the two callers are
/// genuinely different: the conversation list already HOLDS the conversation and
/// must not pay for a round trip to re-fetch it, while a notification only ever
/// carries an id. Neither constructor can express "both" or "neither".
class ChatRouteArgs {
  const ChatRouteArgs.conversation(Conversation this.conversation) : id = null;
  const ChatRouteArgs.id(String this.id) : conversation = null;

  final Conversation? conversation;
  final String? id;
}

class ProfileDetailArgs {
  const ProfileDetailArgs({required this.user, this.isPreview = false});

  final User user;

  /// Hides the like/pass actions and the report menu. Defaults to false because
  /// two of the three call sites show a real other user; the third is the
  /// self-preview, where leaving this off would offer someone their own
  /// like button.
  final bool isPreview;
}

class MediaViewerArgs {
  /// One image, with a hero to expand it out of the thumbnail that opened it.
  const MediaViewerArgs({required String url, required this.heroTag})
      : urls = const [],
        _url = url,
        initialIndex = 0;

  /// A set of images to page through — a profile's photos.
  const MediaViewerArgs.gallery({required this.urls, this.initialIndex = 0})
      : _url = null,
        heroTag = null;

  final List<String> urls;
  final String? _url;
  final int initialIndex;
  final String? heroTag;

  /// The images to show, whichever constructor was used.
  List<String> get images => _url != null ? [_url] : urls;
}

class StoryViewerArgs {
  const StoryViewerArgs({required this.users, required this.initialUserIndex});

  final List<UserStories> users;
  final int initialUserIndex;
}

/// Carries a closure rather than only data: unlike a deep link, this route is
/// never reached by name from outside the app, only pushed by whichever
/// screen owns the list being edited (currently registration step 4) and
/// wants its own callback run when the picker is done.
class LanguagePickerArgs {
  const LanguagePickerArgs({
    required this.initialSelection,
    required this.maxSelection,
    required this.onDone,
  });

  final List<String> initialSelection;
  final int maxSelection;
  final ValueChanged<List<String>> onDone;
}
