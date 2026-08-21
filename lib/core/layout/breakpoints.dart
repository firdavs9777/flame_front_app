import 'package:flutter/widgets.dart';

/// Window size classes, following Material's own breakpoints.
///
/// Two, not three: this app has one phone layout and one "wider than a phone"
/// layout. A medium class would be invented rather than needed, and an unused
/// breakpoint is a decision nobody has actually made.
enum WindowClass { compact, expanded }

/// Material's compact/medium boundary.
const double kExpandedBreakpoint = 600;

/// The swipe deck's ceiling. A full-bleed card on a tablet is absurd — the deck
/// stays phone-sized and centres itself.
const double kDeckMaxWidth = 420;

/// The filter sheet's ceiling on wide screens, so form rows do not stretch into
/// unreadably long lines.
const double kSheetMaxWidth = 560;

WindowClass windowClassOf(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kExpandedBreakpoint
        ? WindowClass.compact
        : WindowClass.expanded;

bool isCompact(BuildContext context) =>
    windowClassOf(context) == WindowClass.compact;
