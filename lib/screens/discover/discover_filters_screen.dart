import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/core/layout/breakpoints.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// The Discover filter sheet.
///
/// Every control here now changes what the deck returns. The distance slider used
/// to save a preference the query ignored; the gender and interest controls were
/// hidden behind a flag for the same reason.
class DiscoverFiltersScreen extends ConsumerStatefulWidget {
  const DiscoverFiltersScreen({super.key});

  @override
  ConsumerState<DiscoverFiltersScreen> createState() =>
      _DiscoverFiltersScreenState();
}

class _DiscoverFiltersScreenState extends ConsumerState<DiscoverFiltersScreen> {
  bool _isSaving = false;

  Future<void> _applyFilters() async {
    setState(() => _isSaving = true);
    final saved = await ref
        .read(filterProvider.notifier)
        .savePreferencesToApi();
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!saved) {
      // Stay open. A sheet that closes on a failed save looks saved.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.filterSaveFailed),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    // Clear rather than merge: the cards already held were chosen under the old
    // filters, so keeping them reads as the new ones not working.
    ref.read(discoveryProvider.notifier).clearAndReload();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(filterProvider);
    final locationKnown =
        ref.watch(locationRefresherProvider).availability !=
        LocationAvailability.denied;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.filterTitle),
        actions: [
          TextButton(
            onPressed: () => ref.read(filterProvider.notifier).reset(),
            child: Text(
              context.l10n.filterReset,
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          // Form rows stretched across a tablet are unreadable.
          constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
          child: ListView(
            key: const ValueKey('filters-body'),
            padding: const EdgeInsets.all(20),
            children: [
              _SectionTitle(context.l10n.filterAgeRange),
              const SizedBox(height: 8),
              Text(
                '${filters.minAge} – ${filters.maxAge}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.onSurface,
                ),
              ),
              RangeSlider(
                values: RangeValues(
                  filters.minAge.toDouble(),
                  filters.maxAge.toDouble(),
                ),
                min: 18,
                max: 65,
                divisions: 47,
                activeColor: AppTheme.primaryColor,
                labels: RangeLabels(
                  filters.minAge.toString(),
                  filters.maxAge.toString(),
                ),
                onChanged: (values) => ref
                    .read(filterProvider.notifier)
                    .setAgeRange(values.start.toInt(), values.end.toInt()),
              ),
              const SizedBox(height: 24),

              _SectionTitle(context.l10n.filterDistance),
              const SizedBox(height: 8),
              Text(
                '${filters.maxDistance.toInt()} km',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: locationKnown
                      ? context.onSurface
                      : context.secondaryText,
                ),
              ),
              Slider(
                value: filters.maxDistance,
                min: 1,
                max: 100,
                divisions: 99,
                activeColor: AppTheme.primaryColor,
                label: '${filters.maxDistance.toInt()} km',
                // Disabled rather than silently ineffective. A control that
                // cannot work must not look like one that can — that was the
                // original defect on this screen.
                onChanged: locationKnown
                    ? (value) => ref
                          .read(filterProvider.notifier)
                          .setMaxDistance(value)
                    : null,
              ),
              if (!locationKnown)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.l10n.filterDistanceNeedsLocation,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              _SectionTitle(context.l10n.filterShowMe),
              const SizedBox(height: 12),
              _GenderSelector(
                selectedGender: filters.genderPreference,
                onChanged: (gender) => ref
                    .read(filterProvider.notifier)
                    .setGenderPreference(gender),
              ),
              const SizedBox(height: 24),

              _SectionTitle(context.l10n.filterInterests),
              const SizedBox(height: 4),
              Text(
                context.l10n.filterInterestsHint(kMaxInterestFilter),
                style: TextStyle(fontSize: 13, color: context.secondaryText),
              ),
              const SizedBox(height: 12),
              _InterestsSelector(
                selected: filters.interests,
                onToggle: (token) =>
                    ref.read(filterProvider.notifier).toggleInterest(token),
              ),
              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _isSaving ? null : _applyFilters,
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.onPrimary,
                        ),
                      )
                    : Text(context.l10n.filterApply),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: context.onSurface,
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({
    required this.selectedGender,
    required this.onChanged,
  });

  final Gender? selectedGender;
  final ValueChanged<Gender?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _option(context, null, context.l10n.filterEveryone),
        ...Gender.values.map((g) => _option(context, g, g.displayName)),
      ],
    );
  }

  Widget _option(BuildContext context, Gender? gender, String label) {
    final isSelected = selectedGender == gender;
    return GestureDetector(
      onTap: () => onChanged(gender),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : context.fill,
          borderRadius: BorderRadius.circular(20),
        ),
        // No fixed height around text: a large system font must wrap, not clip.
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? context.onPrimary : context.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _InterestsSelector extends StatelessWidget {
  const _InterestsSelector({required this.selected, required this.onToggle});

  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final atCap = selected.length >= kMaxInterestFilter;

    // Wrap, not a horizontal scroller: at a large text scale the chips need to
    // flow onto more lines rather than run off the edge.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kInterests.map((interest) {
        final isSelected = selected.contains(interest.token);
        // At the cap, unselected chips are inert — the backend rejects a longer
        // list, so offering an eleventh would be offering a failure.
        final enabled = isSelected || !atCap;
        return GestureDetector(
          onTap: enabled ? () => onToggle(interest.token) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? interest.color.withValues(alpha: 0.15)
                  : context.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? interest.color : context.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  interest.icon,
                  size: 16,
                  color: isSelected
                      ? interest.color
                      : (enabled ? context.secondaryText : context.divider),
                ),
                const SizedBox(width: 6),
                Text(
                  interest.label(context.l10n),
                  style: TextStyle(
                    color: isSelected
                        ? interest.color
                        : (enabled ? context.onSurface : context.secondaryText),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
