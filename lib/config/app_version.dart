/// The shipping version, as one value.
///
/// It was written out three times — the Settings footer, the licence page and
/// `pubspec.yaml` — so two of them were free to go stale, and had: the footer
/// and the licence page will keep saying "v1.0.0" through every release until
/// someone remembers to edit both by hand.
///
/// `pubspec.yaml` is still the source of truth, because that is what the build
/// stamps into the binary. This mirrors it, and `test/config/app_version_test`
/// fails the build if the two ever disagree.
const String kAppVersion = '1.0.0';
