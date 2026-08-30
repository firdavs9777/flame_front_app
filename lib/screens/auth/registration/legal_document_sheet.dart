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

class _Section {
  final String heading;
  final String body;
  const _Section(this.heading, this.body);
}

// ---------------------------------------------------------------------------
// The same documents published at flamedating.net/terms and /privacy, kept in
// the app so they are readable during signup without leaving the flow and
// without a network connection.
//
// THEY MUST STAY IN SYNC. If you change one, change the other in the same
// commit — docs/legal/{terms,privacy}.html in this repo is the canonical copy.
// Every factual claim here was checked against the codebase; the wording is a
// draft pending review by counsel.
// ---------------------------------------------------------------------------

const List<_Section> _termsSections = [
  _Section('1. Who can use Flame',
      'You must be at least 18, legally allowed to use a dating service where '
          'you live, and not previously removed from Flame. One person, one '
          'account.'),
  _Section('2. Your account',
      'Keep your password to yourself — anything done through your account is '
          'treated as done by you. Tell us at support@flamedating.net if you '
          'think someone else has access. If you sign in with Google, that '
          'account controls access to your Flame account.'),
  _Section('3. Your profile must be you',
      'Use your own photos, of yourself, recent enough to be recognisable. '
          'Your main photo must contain your face — Flame checks for one on '
          'your device before the photo can be used. Do not impersonate anyone '
          'or post someone else\'s pictures.'),
  _Section('4. What is not allowed',
      'Harassment, threats, stalking or intimidation. Hate speech. Nudity or '
          'sexual content in photos or stories. Sexual content involving '
          'minors, in any form — this is reported to the authorities without '
          'exception. Asking other users for money, promoting anything, or '
          'recruiting. Prostitution, trafficking or arranging anything '
          'illegal. Sharing someone else\'s private information, including '
          'screenshots of your conversations. Fake accounts, bots, scraping or '
          'automating the app. Trying to break, overload or reverse engineer '
          'the service.\n\n'
          'If you see any of this, use Report inside the app. You can also '
          'block anyone at any time — blocking is immediate and mutual.'),
  _Section('5. What you post stays yours',
      'Your photos and messages are yours. You give us permission to host, '
          'copy and display them for the purpose of running Flame — showing '
          'your profile to other users and delivering your messages — and '
          'nothing else. That permission ends when you delete the content or '
          'your account.'),
  _Section('6. Translation',
      'Translations are produced automatically and may be wrong, clumsy or '
          'miss the tone of the original. Do not rely on one for anything that '
          'matters. Tapping Translate sends that message\'s text to our '
          'translation provider; the Privacy Policy explains exactly what is '
          'sent.'),
  _Section('7. Meeting people is your decision',
      'We do not run background checks on anyone. Requiring a face in a photo '
          'makes fake profiles harder; it does not make anyone safe. We do not '
          'verify identity, criminal history, marital status, or anything '
          'anyone tells you.\n\n'
          'You are meeting strangers, and you do so at your own risk. Meet in '
          'public. Tell someone where you are going. Do not send money to '
          'anyone you have not met, whatever they tell you. If something feels '
          'wrong, leave.'),
  _Section('8. Payments',
      'Flame is currently free. There are no subscriptions and no in-app '
          'purchases. If we introduce paid features we will publish the terms '
          'before we do.'),
  _Section('9. Ending things',
      'You can delete your account at any time in Settings → Delete account. '
          'It is immediate and permanent. We may suspend or remove an account '
          'that breaks these terms, immediately and without warning where it '
          'puts other people at risk.'),
  _Section('10. What we do and do not promise',
      'We work to keep Flame running and to fix what breaks, but we do not '
          'promise it will be uninterrupted, error free, or that you will meet '
          'anyone. To the extent the law allows, we are not liable for what '
          'other users do, for what happens when you meet someone, or for '
          'indirect losses. Nothing here limits liability that cannot lawfully '
          'be limited, and if you are a consumer your statutory rights are '
          'unaffected.'),
  _Section('11. Changes',
      'We may update these terms. We will tell you in the app before anything '
          'material takes effect. The current version is always at '
          'flamedating.net/terms.'),
];

const List<_Section> _privacySections = [
  _Section('1. What we collect',
      'What you give us: email and password (stored only as a bcrypt hash — we '
          'cannot read yours), name, age, gender, who you want to meet, bio, '
          'interests, photos, your precise location, and the messages, stories '
          'and reports you send.\n\n'
          'What we record as you use Flame: who you liked, passed on, matched '
          'with or blocked; whether you are online and when you were last '
          'active; your preferences and settings; and a device token for each '
          'device, so we can send push notifications.'),
  _Section('2. What we do not collect',
      'Flame contains no analytics SDK, no crash-reporting SDK and no '
          'advertising SDK. We do not track you across other apps or websites, '
          'we do not build advertising profiles, and we do not sell your data. '
          'There is nothing to opt out of because there is nothing running.'),
  _Section('3. Sensitive information',
      'Your gender and who you are looking to meet may together reveal '
          'something about your sexual orientation, which is special category '
          'data in the UK and EU. We process it only to run the matching Flame '
          'exists to provide, and only because you chose to provide it. You '
          'can change either field at any time, or delete your account.'),
  _Section('4. Photos and face detection',
      'Your main photo must contain a detectable human face. That check runs '
          'entirely on your phone: the image is analysed locally and only the '
          'result — a face was found, or was not — decides whether the photo '
          'can be used.\n\n'
          'We do not run face recognition, do not compute a faceprint or any '
          'biometric identifier, and do not compare your face against any '
          'database. Photos are not sent anywhere for this check.'),
  _Section('5. Who else processes your data',
      'DigitalOcean Spaces stores your photos and story media (United States). '
          'Mailgun sends our emails. Google provides Sign in with Google and '
          'delivers push notifications. OpenAI translates individual messages '
          '— see the next section.'),
  _Section('6. Message translation',
      'This is not automatic. When, and only when, you tap Translate on a '
          'message, the text of that one message is sent to OpenAI to be '
          'translated and the translation is returned to you. Messages you '
          'never translate are never sent. We do not send the sender\'s name, '
          'your identity, or anything else about the conversation.\n\n'
          'If you would rather no message text left our servers, do not use '
          'the translate button.'),
  _Section('7. Where your data is held',
      'Flame\'s servers and database are hosted in the United States. If you '
          'use Flame from elsewhere, your information is transferred there. We '
          'rely on the Standard Contractual Clauses, and the UK Addendum where '
          'it applies, for those transfers.'),
  _Section('8. Deleting your account',
      'Settings → Delete account. It is immediate and cannot be undone. We '
          'erase your photos, messages and conversations, matches, every like '
          'and pass you made and every one made about you, your stories, the '
          'reports you filed, and every signed-in session.\n\n'
          'Your email address is released rather than kept — we no longer hold '
          'it, and you are free to sign up again later with the same address. '
          'What remains is an anonymous record that the account existed, so '
          'that conversations other people had do not break.'),
  _Section('9. Your rights',
      'You can ask us to give you a copy of your data, correct it, delete it, '
          'restrict or object to how we use it, or send it to another service. '
          'Most of this is in the app already. For anything else, write to '
          'privacy@flamedating.net and we will respond within one month.'),
  _Section('10. Security',
      'Passwords are stored as bcrypt hashes. Password reset codes are stored '
          'hashed, expire after fifteen minutes, are single use, and stop '
          'working after five wrong attempts. Traffic is encrypted in transit. '
          'Changing your password signs out every other device.\n\n'
          'No service can promise perfect security and we will not pretend '
          'otherwise. If a breach affects you we will tell you.'),
  _Section('11. Contact',
      'Privacy questions go to privacy@flamedating.net. The current version of '
          'this policy is always at flamedating.net/privacy.'),
];
