import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/theme/app_theme.dart';

const List<String> _kAlphabet = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

/// Heights, in logical pixels, of the things this list is built from. The
/// A-Z index sums these to find where a section actually begins, so they are
/// the layout contract rather than decoration: a one-line and a two-line
/// Material ListTile, the divider under Recommended (`Divider(height: 24)`),
/// and the two header paddings plus their line boxes.
const double _kRowHeight = 56.0;
const double _kRowWithSubtitleHeight = 72.0;
const double _kSectionHeaderHeight = 32.0;
const double _kRecommendedHeaderHeight = 30.0;
const double _kDividerHeight = 24.0;

/// The A-Z section a language belongs under.
///
/// Never indexes a string it has not checked first. `name` is blank on rows
/// the backend really serves, and blank on any [Language] built directly
/// rather than parsed -- and a single `RangeError` here takes the whole
/// picker down with a red screen.
@visibleForTesting
String sectionLetterFor(Language lang) {
  for (final candidate in [lang.name, lang.nativeName, lang.code]) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) return trimmed[0].toUpperCase();
  }
  return '#';
}

/// What one entry of the picker's list is.
enum LanguagePickerSlotKind { recommendedHeader, row, divider, sectionHeader }

/// One entry in the picker's flat list, with the height it will occupy.
@immutable
class LanguagePickerSlot {
  const LanguagePickerSlot({
    required this.kind,
    required this.height,
    this.language,
    this.letter,
  });

  final LanguagePickerSlotKind kind;
  final double height;

  /// Set on [LanguagePickerSlotKind.row].
  final Language? language;

  /// Set on [LanguagePickerSlotKind.sectionHeader] -- what the A-Z index
  /// scrolls to.
  final String? letter;
}

/// The picker's list expressed as data before it is expressed as widgets.
///
/// The A-Z index used to scroll to `position-in-the-alphabetical-list * 56`,
/// which ignored the Recommended header, its rows, the divider under it, and
/// one header per letter section -- so tapping "M" landed hundreds of pixels
/// short and the error compounded down the alphabet. Laying the list out as
/// slots first means the index sums what is genuinely above a section instead
/// of assuming everything above it is a row.
@visibleForTesting
class LanguagePickerLayout {
  LanguagePickerLayout({
    required List<Language> recommended,
    required List<Language> rest,
  }) : slots = _slotsFor(recommended, rest);

  final List<LanguagePickerSlot> slots;

  static List<LanguagePickerSlot> _slotsFor(
    List<Language> recommended,
    List<Language> rest,
  ) {
    final out = <LanguagePickerSlot>[];
    if (recommended.isNotEmpty) {
      out.add(const LanguagePickerSlot(
        kind: LanguagePickerSlotKind.recommendedHeader,
        height: _kRecommendedHeaderHeight,
      ));
      out.addAll(recommended.map(_rowSlot));
      out.add(const LanguagePickerSlot(
        kind: LanguagePickerSlotKind.divider,
        height: _kDividerHeight,
      ));
    }

    String? section;
    for (final lang in rest) {
      final letter = sectionLetterFor(lang);
      if (letter != section) {
        section = letter;
        out.add(LanguagePickerSlot(
          kind: LanguagePickerSlotKind.sectionHeader,
          height: _kSectionHeaderHeight,
          letter: letter,
        ));
      }
      out.add(_rowSlot(lang));
    }
    return out;
  }

  static LanguagePickerSlot _rowSlot(Language lang) => LanguagePickerSlot(
        kind: LanguagePickerSlotKind.row,
        height: lang.name == lang.nativeName
            ? _kRowHeight
            : _kRowWithSubtitleHeight,
        language: lang,
      );

  /// Whether any language is filed under [letter].
  bool hasLetter(String letter) => slots.any((s) => s.letter == letter);

  /// Where [letter]'s section header starts, or null if there is no such
  /// section.
  double? offsetForLetter(String letter) {
    var offset = 0.0;
    for (final slot in slots) {
      if (slot.letter == letter) return offset;
      offset += slot.height;
    }
    return null;
  }
}

/// A picker for `languagesSpoken` / `languagesLearning`, not a chip grid.
///
/// 127+ languages will not fit as chips. Mirrors BananaTalk's
/// `language_picker_screen.dart`: search across the English AND native name,
/// a Recommended shortlist above the alphabetical list (hidden once a search
/// is typed), and an A-Z index once the list is long enough to need one.
///
/// Adapted for Flame: multi-select up to [maxSelection] rather than a single
/// pick, backed by the Riverpod [languageCatalogProvider] rather than a
/// caller-supplied list, and it hands back codes rather than a [Language].
///
/// A language already in the Recommended shortlist is not repeated in the
/// alphabetical section below it -- unlike BananaTalk, which lists it twice.
/// Showing 한국어 once here rather than twice is deliberate: the shortlist and
/// the full list are two ways to reach the same entry, not two entries.
class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({
    super.key,
    required this.initialSelection,
    required this.maxSelection,
    required this.onDone,
  });

  /// ISO 639-1 codes already chosen, e.g. resuming from a previous visit.
  final List<String> initialSelection;

  /// The most codes [onDone] may be called with. A tap that would exceed it
  /// is ignored -- the counter in the app bar is the warning, visible before
  /// the tap rather than after it.
  final int maxSelection;

  /// Called with the selected codes when Done is tapped. The caller decides
  /// whether/how to pop -- this screen never pops itself.
  final ValueChanged<List<String>> onDone;

  @override
  ConsumerState<LanguagePickerScreen> createState() =>
      _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  late final List<String> _selected = List.of(widget.initialSelection);
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle(String code) {
    setState(() {
      if (_selected.contains(code)) {
        _selected.remove(code);
      } else if (_selected.length < widget.maxSelection) {
        _selected.add(code);
      }
      // Beyond the cap the tap is silently ignored: the count already shown
      // in the app bar is the warning, not a snackbar after the fact.
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(languageCatalogProvider);

    return catalogAsync.when(
      data: (catalog) => _buildScaffold(context, catalog),
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.languagesPickerTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      // The picker sits behind registration. Empty is not an option, so an
      // unreachable catalogue still renders the bundled fallback rather than
      // an error screen or a blank list.
      error: (_, _) => _buildScaffold(context, kLanguageFallback),
    );
  }

  Widget _buildScaffold(BuildContext context, List<Language> catalog) {
    final query = _searchController.text.trim().toLowerCase();
    final showRecommended = query.isEmpty;

    bool matchesQuery(Language l) =>
        query.isEmpty ||
        l.name.toLowerCase().contains(query) ||
        l.nativeName.toLowerCase().contains(query);

    List<Language> sorted(Iterable<Language> source) {
      final out = source.where(matchesQuery).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return out;
    }

    final recommended = showRecommended
        ? sorted(catalog.where((l) => kRecommendedCodes.contains(l.code)))
        : const <Language>[];
    // A language already shown in Recommended is not repeated below it.
    final rest = sorted(
      showRecommended
          ? catalog.where((l) => !kRecommendedCodes.contains(l.code))
          : catalog,
    );

    final layout = LanguagePickerLayout(recommended: recommended, rest: rest);
    final showIndex = showRecommended && rest.length > 20;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.languagesPickerTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${_selected.length}/${widget.maxSelection}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _selected.length >= widget.maxSelection
                      ? AppTheme.primaryColor
                      : Colors.grey[600],
                ),
              ),
            ),
          ),
          TextButton(
            key: const Key('language_picker_done'),
            onPressed: () => widget.onDone(List.of(_selected)),
            child: Text(context.l10n.commonSave),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.commonSearchHint,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: recommended.isEmpty && rest.isEmpty
                ? Center(
                    child: Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey[300],
                    ),
                  )
                : Stack(
                    children: [
                      ListView(
                        controller: _scrollController,
                        children: [
                          for (final slot in layout.slots)
                            _slotWidget(context, slot),
                        ],
                      ),
                      if (showIndex) _alphabetIndex(layout),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _slotWidget(BuildContext context, LanguagePickerSlot slot) {
    switch (slot.kind) {
      case LanguagePickerSlotKind.recommendedHeader:
        // Matches BananaTalk's reference header style: a plain bold label,
        // not an icon standing in for one.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            context.l10n.languagesRecommended,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        );
      case LanguagePickerSlotKind.divider:
        return const Divider(height: _kDividerHeight);
      case LanguagePickerSlotKind.sectionHeader:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            slot.letter!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
            ),
          ),
        );
      case LanguagePickerSlotKind.row:
        return _row(slot.language!);
    }
  }

  Widget _row(Language lang) {
    final isSelected = _selected.contains(lang.code);
    final showSubtitle = lang.name != lang.nativeName;

    return ListTile(
      onTap: () => _toggle(lang.code),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lang.flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              lang.nativeName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      subtitle: showSubtitle ? Text(lang.name) : null,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
          : null,
      selected: isSelected,
    );
  }

  Widget _alphabetIndex(LanguagePickerLayout layout) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 24,
        alignment: Alignment.centerRight,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _kAlphabet.length,
          itemBuilder: (context, index) {
            final letter = _kAlphabet[index];
            final hasLanguage = layout.hasLetter(letter);
            return GestureDetector(
              onTap: hasLanguage ? () => _scrollToLetter(layout, letter) : null,
              child: SizedBox(
                height: 18,
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasLanguage
                          ? AppTheme.primaryColor
                          : Colors.grey[300],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _scrollToLetter(LanguagePickerLayout layout, String letter) {
    final offset = layout.offsetForLetter(letter);
    if (offset == null || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
