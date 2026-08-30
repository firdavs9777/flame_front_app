import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// The app's legal text and the published documents drifted apart twice without
// anyone noticing, because noticing means reading two documents side by side.
//
// The published privacy policy had grown "Who we are", "How long we keep
// things" and "Changes"; the app had grown "What we do not collect", "Message
// translation" and "Contact"; and the app never showed the Terms' "Law"
// section at all. They also disagreed about how to contact us — one promised
// support@flamedating.net, the other gave bananatalkmain@gmail.com.
//
// docs/legal/*.html is generated from the sheet now. This fails when the
// checked-in HTML no longer matches, which is the only moment the drift is
// cheap to fix.

void main() {
  test('docs/legal/*.html matches the in-app sheet', () {
    final result = Process.runSync(
      'python3',
      ['tool/legal/render_legal.py', '--check'],
    );
    expect(
      result.exitCode,
      0,
      reason: 'Published legal documents have drifted from the app:\n'
          '${result.stdout}${result.stderr}\n'
          'Regenerate with: python3 tool/legal/render_legal.py',
    );
  });

  test('neither document promises a mailbox we do not answer', () {
    // support@ and privacy@flamedating.net were written into the documents
    // before either address existed. A policy that names an unread inbox is a
    // promise, not a placeholder — swap these back the moment they are real.
    for (final path in const [
      'docs/legal/terms.html',
      'docs/legal/privacy.html',
      'lib/screens/auth/registration/legal_document_sheet.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('@flamedating.net')),
        reason: '$path names an address that does not receive mail',
      );
    }
  });
}
