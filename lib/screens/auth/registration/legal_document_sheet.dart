import 'package:flutter/material.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

enum LegalDoc { terms, privacy }

/// Opens the Terms of Service or Privacy Policy as a scrollable modal sheet.
Future<void> showLegalDocumentSheet(BuildContext context, LegalDoc doc) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LegalDocumentSheet(doc: doc),
  );
}

class _LegalDocumentSheet extends StatelessWidget {
  const _LegalDocumentSheet({required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final title = doc == LegalDoc.terms
        ? context.l10n.registerTermsOfService
        : context.l10n.registerPrivacyPolicy;
    final sections =
        doc == LegalDoc.terms ? _termsSections : _privacySections;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: AppTypography.headlineSmall),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _PlaceholderBanner(),
                  const SizedBox(height: 16),
                  for (final s in sections) ...[
                    Text(s.heading, style: AppTypography.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      s.body,
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.gray700),
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: AppButton(
                  text: context.l10n.legalClose,
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppRadius.borderMD,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Placeholder text — replace with your finalized, '
              'counsel-approved legal copy before launch.',
              style: AppTypography.labelMedium.copyWith(color: AppColors.gray800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section {
  final String heading;
  final String body;
  const _Section(this.heading, this.body);
}

// ---------------------------------------------------------------------------
// PLACEHOLDER legal copy. Structured like real documents so the UX is faithful,
// but the wording is not legal advice — replace before launch.
// ---------------------------------------------------------------------------

const _lorem =
    'This section is placeholder content. Replace it with the finalized wording '
    'provided by your legal counsel. It should clearly describe the relevant '
    'terms in plain, accurate language for your users.';

const List<_Section> _termsSections = [
  _Section('1. Acceptance of Terms',
      'By creating an account you agree to these Terms of Service. $_lorem'),
  _Section('2. Eligibility',
      'You must be at least 18 years old to use Flame. $_lorem'),
  _Section('3. Your Account',
      'You are responsible for the security of your account and credentials. $_lorem'),
  _Section('4. Community Guidelines',
      'You agree to treat other members with respect and not to harass, '
          'impersonate, or share prohibited content. $_lorem'),
  _Section('5. Your Content',
      'You retain ownership of the photos and text you post, and grant Flame a '
          'license to display them within the service. $_lorem'),
  _Section('6. Prohibited Conduct',
      'Spam, solicitation, illegal activity, and abuse are not permitted. $_lorem'),
  _Section('7. Termination',
      'We may suspend or terminate accounts that violate these terms. $_lorem'),
  _Section('8. Disclaimers & Liability',
      'The service is provided "as is" to the extent permitted by law. $_lorem'),
  _Section('9. Changes to These Terms',
      'We may update these terms and will notify you of material changes. $_lorem'),
  _Section('10. Contact',
      'Questions about these terms can be sent to support@flame.app. $_lorem'),
];

const List<_Section> _privacySections = [
  _Section('1. Information We Collect',
      'We collect the profile details, photos, and usage data you provide. $_lorem'),
  _Section('2. How We Use Your Data',
      'We use your data to operate matching, messaging, and safety features. $_lorem'),
  _Section('3. Location Data',
      'With your permission we use approximate location to show nearby matches. $_lorem'),
  _Section('4. Sharing',
      'We do not sell your personal data. Limited sharing occurs with service '
          'providers who help us run the app. $_lorem'),
  _Section('5. Data Retention',
      'We keep your data while your account is active and for a limited period '
          'afterward. $_lorem'),
  _Section('6. Your Rights',
      'You can access, correct, export, or delete your personal data. $_lorem'),
  _Section('7. Security',
      'We use industry-standard measures to protect your information. $_lorem'),
  _Section('8. Children’s Privacy',
      'Flame is not directed to anyone under 18. $_lorem'),
  _Section('9. Changes to This Policy',
      'We will post updates to this policy and notify you of material changes. $_lorem'),
  _Section('10. Contact',
      'Privacy questions can be sent to privacy@flame.app. $_lorem'),
];
