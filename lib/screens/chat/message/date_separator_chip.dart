import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/theme/app_tokens.dart';

/// The `Today` / `Yesterday` / date chip between two days of messages.
class DateSeparatorChip extends StatelessWidget {
  const DateSeparatorChip({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            // The clock is read here, at render time, rather than baked into the
            // row — which is what lets a session left open across midnight
            // relabel itself.
            chatDayLabel(day, DateTime.now(), context.l10n),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: context.secondaryText),
          ),
        ),
      ),
    );
  }
}
