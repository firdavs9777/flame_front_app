import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(filterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery Settings'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(filterProvider.notifier).reset();
            },
            child: Text(
              'Reset',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Age range
          _buildSectionTitle('Age Range'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${filters.minAge} - ${filters.maxAge}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
            onChanged: (values) {
              ref.read(filterProvider.notifier).setAgeRange(
                    values.start.toInt(),
                    values.end.toInt(),
                  );
            },
          ),
          const SizedBox(height: 24),

          // Distance
          _buildSectionTitle('Maximum Distance'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${filters.maxDistance.toInt()} km',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Slider(
            value: filters.maxDistance,
            min: 1,
            max: 100,
            divisions: 99,
            activeColor: AppTheme.primaryColor,
            label: '${filters.maxDistance.toInt()} km',
            onChanged: (value) {
              ref.read(filterProvider.notifier).setMaxDistance(value);
            },
          ),
          const SizedBox(height: 24),

          // Looking for
          _buildSectionTitle('Show Me'),
          const SizedBox(height: 12),
          _GenderSelector(
            selectedGender: filters.genderPreference,
            onChanged: (gender) {
              ref.read(filterProvider.notifier).setGenderPreference(gender);
            },
          ),
          const SizedBox(height: 24),

          // Online only
          _buildSectionTitle('Filters'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Only show online users'),
            subtitle: const Text('See people who are currently active'),
            value: filters.onlineOnly,
            activeColor: AppTheme.primaryColor,
            contentPadding: EdgeInsets.zero,
            onChanged: (_) {
              ref.read(filterProvider.notifier).toggleOnlineOnly();
            },
          ),
          const SizedBox(height: 24),

          // Interests filter
          _buildSectionTitle('Interests'),
          const SizedBox(height: 12),
          _InterestsSelector(
            selectedInterests: filters.interests,
            onChanged: (interests) {
              ref.read(filterProvider.notifier).setInterests(interests);
            },
          ),
          const SizedBox(height: 40),

          // Apply button
          ElevatedButton(
            onPressed: () {
              // Refresh discovery with new filters
              ref.read(discoveryProvider.notifier).loadPotentialMatches(refresh: true);
              Navigator.pop(context);
            },
            child: const Text('Apply Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  final Gender? selectedGender;
  final ValueChanged<Gender?> onChanged;

  const _GenderSelector({
    required this.selectedGender,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildOption(null, 'Everyone'),
        ...Gender.values.map((g) => _buildOption(g, g.displayName)),
      ],
    );
  }

  Widget _buildOption(Gender? gender, String label) {
    final isSelected = selectedGender == gender;
    return GestureDetector(
      onTap: () => onChanged(gender),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _InterestsSelector extends StatelessWidget {
  final List<String> selectedInterests;
  final ValueChanged<List<String>> onChanged;

  const _InterestsSelector({
    required this.selectedInterests,
    required this.onChanged,
  });

  static const allInterests = [
    'Travel',
    'Music',
    'Movies',
    'Sports',
    'Fitness',
    'Food',
    'Art',
    'Gaming',
    'Reading',
    'Photography',
    'Coffee',
    'Hiking',
    'Dancing',
    'Cooking',
    'Yoga',
    'Nature',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allInterests.map((interest) {
        final isSelected = selectedInterests.contains(interest);
        return GestureDetector(
          onTap: () {
            final newList = List<String>.from(selectedInterests);
            if (isSelected) {
              newList.remove(interest);
            } else {
              newList.add(interest);
            }
            onChanged(newList);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor
                    : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              interest,
              style: TextStyle(
                color: isSelected ? AppTheme.primaryColor : Colors.black87,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
