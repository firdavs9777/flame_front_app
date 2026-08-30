#!/usr/bin/env python3
"""Render docs/legal/*.html from the in-app legal sheet.

    python3 tool/legal/render_legal.py            # write
    python3 tool/legal/render_legal.py --check    # exit 1 if they differ

The two copies drifted twice: the published privacy policy grew "Who we are",
"How long we keep things" and "Changes" while the app grew "What we do not
collect", "Message translation" and "Contact", and the app was missing the
Terms' "Law" section entirely. Worse, they disagreed about how to contact us.

Nobody notices that by reading. So there is one source now — the Dart sheet a
user actually taps through — and the website is generated from it.
"""
import html
import re
import sys
from pathlib import Path

DART = Path('lib/screens/auth/registration/legal_document_sheet.dart')
OUT = Path('docs/legal')
UPDATED = '30 August 2026'

DOCS = {
    '_termsSections': ('terms.html', 'Terms of Service', 'Flame Terms of Service',
                       'privacy.html', 'Privacy Policy'),
    '_privacySections': ('privacy.html', 'Privacy Policy', 'Flame Privacy Policy',
                         'terms.html', 'Terms of Service'),
}

BANNER = """<!--
  DRAFT — not legal advice. Every factual claim below was checked against the
  Flame codebase and is accurate as of the date shown. The LAW around it still
  needs a lawyer, particularly the sensitive-information section: gender
  combined with who you are looking for can imply sexual orientation, which is
  special category data under UK/EU GDPR Article 9 and needs an explicit
  lawful basis.

  GENERATED FILE — do not edit. Source: the section lists in
  lib/screens/auth/registration/legal_document_sheet.dart.
  Regenerate with: python3 tool/legal/render_legal.py
-->"""


def sections(source: str, name: str):
    """Every (title, body) in one `const List<_Section> <name>` literal."""
    start = source.index(f'const List<_Section> {name} = [')
    body = source[start:source.index('\n];', start)]
    out = []
    for m in re.finditer(r"_Section\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*((?:'(?:[^'\\]|\\.)*'\s*)+)\)",
                         body):
        title = unquote(m.group(1))
        text = ''.join(unquote(p) for p in re.findall(r"'((?:[^'\\]|\\.)*)'", m.group(2)))
        out.append((title, text))
    return out


def unquote(literal: str) -> str:
    """Dart single-quoted string body -> the text it denotes."""
    return (literal.replace("\\n", "\n").replace("\\'", "'")
                   .replace('\\"', '"').replace('\\\\', '\\'))


def render(title, heading, sibling_href, sibling_label, secs):
    parts = [
        '<!doctype html>', BANNER, '<html lang="en">', '<head>',
        '  <meta charset="utf-8">',
        '  <meta name="viewport" content="width=device-width, initial-scale=1">',
        f'  <title>{html.escape(title)} — Flame</title>',
        '  <link rel="stylesheet" href="_style.css">',
        '</head>', '<body>', '<div class="wrap">', '<header>',
        f'  <h1>{html.escape(heading)}</h1>',
        f'  <p class="meta">Last updated: {UPDATED} &middot; '
        '<a href="https://flamedating.net">flamedating.net</a></p>',
        '</header>', '',
    ]
    for name, text in secs:
        parts.append(f'<h2>{html.escape(name)}</h2>')
        for para in text.split('\n\n'):
            parts.append(f'<p>{html.escape(para.strip())}</p>')
        parts.append('')
    parts += [
        '<footer>',
        f'  <p>Flame &middot; <a href="{sibling_href}">{html.escape(sibling_label)}</a>'
        ' &middot; <a href="mailto:bananatalkmain@gmail.com">bananatalkmain@gmail.com</a></p>',
        '</footer>', '</div>', '</body>', '</html>', '',
    ]
    return '\n'.join(parts)


def main(check=False):
    source = DART.read_text()
    drift = []
    for list_name, (fname, title, heading, sib, sib_label) in DOCS.items():
        secs = sections(source, list_name)
        if not secs:
            raise SystemExit(f'no sections parsed from {list_name}')
        want = render(title, heading, sib, sib_label, secs)
        path = OUT / fname
        if check:
            have = path.read_text() if path.exists() else ''
            if have != want:
                drift.append(fname)
            print(f'  {fname:14} {len(secs):>2} sections  '
                  f'{"DRIFTED" if have != want else "in sync"}')
        else:
            path.write_text(want)
            print(f'  {fname:14} {len(secs):>2} sections written')
    if drift:
        raise SystemExit(
            f'\n{", ".join(drift)} differ from the app. '
            'Run: python3 tool/legal/render_legal.py')


if __name__ == '__main__':
    main(check='--check' in sys.argv)
