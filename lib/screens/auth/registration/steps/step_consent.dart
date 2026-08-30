import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/auth/registration/widgets/terms_consent.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

/// The Terms and Privacy gate for someone who signed in with Apple, Google or
/// Facebook.
///
/// The email path has always had this on its first step. The social path had
/// nothing: the provider returned, the backend created the account, and the
/// user landed in profile completion having agreed to nothing — the welcome
/// screen's notice is passive text with no way to open either document.
///
/// It is a step of its own rather than a checkbox tacked onto "About You".
/// A legal gate underneath name, age and gender fields is easy to scroll past,
/// and "they must have seen it" is not the position to defend.
class StepConsent extends StatefulWidget {
  const StepConsent({
    super.key,
    required this.accepted,
    required this.onNext,
    required this.onDecline,
  });

  /// Held by the flow, not by this widget, so returning to the step by swiping
  /// back does not silently clear an answer the user already gave.
  final ValueNotifier<bool> accepted;
  final VoidCallback onNext;

  /// Leaving without accepting. The wizard's back arrow does this too, but an
  /// arrow that silently signs you out is not an answer to "I do not agree".
  final VoidCallback onDecline;

  @override
  State<StepConsent> createState() => _StepConsentState();
}

class _StepConsentState extends State<StepConsent> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.accepted,
      builder: (context, accepted, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        // On a card, like every other step. Rendered bare, this sat straight on
        // the wizard's coral gradient — where TermsConsent's grey body text and
        // its primary-coloured links are close enough to the background to read
        // as an empty screen with a heading.
        child: AppCard(
          padding: const EdgeInsets.all(24),
          borderRadius: AppRadius.borderXXL,
          boxShadow: AppShadows.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TermsConsent(
                value: accepted,
                onChanged: (v) => widget.accepted.value = v,
              ),
              const SizedBox(height: 28),
              AppButton(
                text: context.l10n.registerContinue,
                onPressed: accepted ? widget.onNext : null,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: widget.onDecline,
                child: Text(context.l10n.registerConsentDecline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
