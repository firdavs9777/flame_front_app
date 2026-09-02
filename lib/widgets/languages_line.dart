import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/core/languages/language_label.dart';
import 'package:flame/providers/languages_provider.dart';

/// "Speaks 한국어 · Learning English".
///
/// The premise, made visible. Ranking cannot be seen — in a sparse pool it may
/// not even be felt — so this line is what tells someone, and an App Store
/// reviewer, what this app is for within seconds of opening it.
///
/// Renders NOTHING when nothing is declared. Every account created before this
/// feature has empty lists, and a label with no value after it reads as broken
/// data rather than as an absent answer.
class LanguagesLine extends ConsumerWidget {
  const LanguagesLine({
    super.key,
    required this.spoken,
    required this.learning,
    this.style,
  });

  final List<String> spoken;
  final List<String> learning;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull with a fallback rather than AsyncValue.when: this line sits
    // on a deck card, and a spinner where a language should be is worse than
    // a name resolved from the bundled list.
    final catalog =
        ref.watch(languageCatalogProvider).valueOrNull ?? kLanguageFallback;
    String label(String c) => languageLabel(c, catalog);

    final parts = <String>[];

    if (spoken.isNotEmpty) {
      parts.add('${context.l10n.profileSpeaks} ${spoken.map(label).join(', ')}');
    }
    if (learning.isNotEmpty) {
      parts.add('${context.l10n.profileLearning} '
          '${learning.map(label).join(', ')}');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      key: const Key('languages_line'),
      style: style,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }
}
