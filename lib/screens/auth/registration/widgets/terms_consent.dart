import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';
import 'package:flame/theme/app_theme.dart';

/// "I agree to the Terms of Service and Privacy Policy", with both documents
/// openable before agreeing.
///
/// Extracted from the email step so the social path can present the identical
/// gate. It used to exist only on the email step, which meant anyone signing
/// up with Apple or Google reached a finished account having agreed to
/// nothing: the welcome screen's notice is passive text with no way to read
/// either document. An affirmative, informed action is what GDPR asks for and
/// what App Store review expects of a UGC app.
class TermsConsent extends StatefulWidget {
  const TermsConsent({
    super.key,
    required this.value,
    required this.onChanged,
    this.textColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Overrides the label colour for surfaces that are not the default card —
  /// the social step runs on the same gradient the welcome screen uses.
  final Color? textColor;

  @override
  State<TermsConsent> createState() => _TermsConsentState();
}

class _TermsConsentState extends State<TermsConsent> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => showLegalDocumentSheet(context, LegalDoc.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => showLegalDocumentSheet(context, LegalDoc.privacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkStyle = const TextStyle(
      color: AppTheme.primaryColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    final baseStyle = AppTypography.bodySmall
        .copyWith(color: widget.textColor ?? AppColors.gray700, height: 1.4);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: widget.value,
            onChanged: (v) => widget.onChanged(v ?? false),
            activeColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  TextSpan(text: context.l10n.registerAgreePrefix),
                  TextSpan(
                    text: context.l10n.registerTermsOfService,
                    style: linkStyle,
                    recognizer: _termsRecognizer,
                  ),
                  TextSpan(text: context.l10n.registerAgreeConjunction),
                  TextSpan(
                    text: context.l10n.registerPrivacyPolicy,
                    style: linkStyle,
                    recognizer: _privacyRecognizer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
