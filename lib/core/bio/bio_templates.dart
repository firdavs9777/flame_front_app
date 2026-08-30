import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

/// Drafts profile bios from the user's interests, on the device.
///
/// Deliberately templates rather than a model. A generated bio needs a metered
/// outbound call, a provider key on the server, a rate limit, and a prompt-
/// injection story for a field that accepts free text — none of which is worth
/// blocking a release on. The templates cost nothing, work offline, cannot
/// fail, and solve the actual problem: a blank box with no idea what belongs
/// in it.
///
/// The sentences live in the ARBs, so they are written in the reader's
/// language rather than translated out of English. The interest names are
/// localised too — the whole point is that a Korean speaker gets a Korean
/// sentence about 여행, not "Travel".
List<String> bioSuggestions(List<String> interests, AppLocalizations l10n) {
  final labels = interests
      .map((token) => interestLabel(token, l10n))
      .where((label) => label.isNotEmpty)
      .toList();
  if (labels.isEmpty) return const [];

  // Three at most, because a bio that lists ten interests reads like a form.
  // The list separator is deliberately plain: an "A, B and C" join needs a
  // conjunction per language and a rule for two-item lists, which is more
  // grammar than three template sentences are worth.
  final few = labels.take(3).join(', ');

  return [
    l10n.bioTemplateInto(few),
    l10n.bioTemplateFreeTime(few),
    l10n.bioTemplateAskMe(labels.first),
  ];
}
