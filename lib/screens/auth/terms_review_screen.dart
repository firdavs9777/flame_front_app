import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/registration/widgets/terms_consent.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/widgets/kit/kit.dart';

/// Asks an already-signed-in user to accept the Terms and Privacy Policy.
///
/// Consent used to be collected only on the email registration step, and only
/// in the UI — the answer gated a button and was then discarded. So two groups
/// hold accounts having agreed to nothing on record: everyone who signed up
/// before consent was stored, and every social signup, whose path had no
/// checkbox at all.
///
/// The server reports `termsAcceptedAt: null` for them. This is where that is
/// resolved: once, on the next open, before the app is usable.
class TermsReviewScreen extends ConsumerStatefulWidget {
  const TermsReviewScreen({super.key});

  @override
  ConsumerState<TermsReviewScreen> createState() => _TermsReviewScreenState();
}

class _TermsReviewScreenState extends ConsumerState<TermsReviewScreen> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    final result = await UserService().updateProfile(termsAccepted: true);
    if (!mounted) return;

    if (!result.success) {
      setState(() => _saving = false);
      showAuthSnackBar(
        context,
        message: result.error ?? context.l10n.errorGeneric,
        type: AuthSnackBarType.error,
      );
      return;
    }
    // Hand the refreshed user back to the notifier, which is what moves this
    // screen out of the way. Re-reading from the server instead would race the
    // rebuild and could show this screen a second time.
    ref.read(authProvider.notifier).setUser(result.data!);
  }

  /// Declining is not a dismissal. The service cannot be used without these
  /// terms, so the honest outcome is to sign out rather than leave someone
  /// inside an app they have refused the terms of.
  Future<void> _decline() => ref.read(authProvider.notifier).logout();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.termsReviewTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.registerStepConsentSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TermsConsent(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v),
                ),
                const SizedBox(height: 32),
                AppButton(
                  text: l10n.registerContinue,
                  isLoading: _saving,
                  onPressed: _accepted && !_saving ? _accept : null,
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _saving ? null : _decline,
                  child: Text(l10n.registerConsentDecline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
