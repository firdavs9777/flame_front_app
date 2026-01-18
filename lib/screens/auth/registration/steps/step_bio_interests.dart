import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

class StepBioInterests extends StatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepBioInterests({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<StepBioInterests> createState() => _StepBioInterestsState();
}

class _StepBioInterestsState extends State<StepBioInterests> {
  final _bioController = TextEditingController();
  final List<String> _selectedInterests = [];

  static const List<_InterestItem> _availableInterests = [
    _InterestItem('Travel', Icons.flight_takeoff_rounded, Color(0xFF3498DB)),
    _InterestItem('Music', Icons.music_note_rounded, Color(0xFF9B59B6)),
    _InterestItem('Movies', Icons.movie_creation_rounded, Color(0xFFE74C3C)),
    _InterestItem('Food', Icons.restaurant_rounded, Color(0xFFE67E22)),
    _InterestItem('Fitness', Icons.fitness_center_rounded, Color(0xFF27AE60)),
    _InterestItem('Reading', Icons.menu_book_rounded, Color(0xFF8E44AD)),
    _InterestItem('Gaming', Icons.sports_esports_rounded, Color(0xFF2980B9)),
    _InterestItem('Art', Icons.palette_rounded, Color(0xFFD35400)),
    _InterestItem('Photography', Icons.camera_alt_rounded, Color(0xFF16A085)),
    _InterestItem('Sports', Icons.sports_soccer_rounded, Color(0xFF2ECC71)),
    _InterestItem('Cooking', Icons.soup_kitchen_rounded, Color(0xFFF39C12)),
    _InterestItem('Nature', Icons.park_rounded, Color(0xFF1ABC9C)),
    _InterestItem('Coffee', Icons.coffee_rounded, Color(0xFF795548)),
    _InterestItem('Wine', Icons.wine_bar_rounded, Color(0xFFC0392B)),
    _InterestItem('Dancing', Icons.nightlife_rounded, Color(0xFFFF6B6B)),
    _InterestItem('Yoga', Icons.self_improvement_rounded, Color(0xFF00BCD4)),
    _InterestItem('Pets', Icons.pets_rounded, Color(0xFFFF9800)),
    _InterestItem('Tech', Icons.devices_rounded, Color(0xFF607D8B)),
  ];

  @override
  void initState() {
    super.initState();
    _bioController.text = widget.data.bio;
    _selectedInterests.addAll(widget.data.interests);
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bio Section
            const Text(
              'About You',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Write something fun about yourself',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 12),
            _buildBioField()
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Interests Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Interests',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _selectedInterests.length >= 3
                        ? AppTheme.successColor.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedInterests.length}/5 selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedInterests.length >= 3
                          ? AppTheme.successColor
                          : Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select 3-5 interests to help find better matches',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 16),
            _buildInterestsGrid()
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Continue Button
            _buildContinueButton()
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 400.ms),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  Widget _buildBioField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _bioController,
        maxLines: 4,
        maxLength: 300,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'e.g., Coffee enthusiast who loves hiking on weekends. Always up for trying new restaurants!',
          hintStyle: TextStyle(
            color: Colors.grey[400],
            height: 1.5,
          ),
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
          counterStyle: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }

  Widget _buildInterestsGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _availableInterests.map((interest) {
        final isSelected = _selectedInterests.contains(interest.name);

        return GestureDetector(
          onTap: () => _toggleInterest(interest.name),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? interest.color.withOpacity(0.15) : Colors.grey[50],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? interest.color : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  interest.icon,
                  size: 18,
                  color: isSelected ? interest.color : Colors.grey[500],
                ),
                const SizedBox(width: 6),
                Text(
                  interest.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? interest.color : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _toggleInterest(String interest) {
    setState(() {
      if (_selectedInterests.contains(interest)) {
        _selectedInterests.remove(interest);
      } else if (_selectedInterests.length < 5) {
        _selectedInterests.add(interest);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Maximum 5 interests allowed'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _handleContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Continue',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _handleContinue() {
    if (_selectedInterests.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least 3 interests'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    widget.data.bio = _bioController.text.trim();
    widget.data.interests = List.from(_selectedInterests);
    widget.onNext();
  }
}

class _InterestItem {
  final String name;
  final IconData icon;
  final Color color;

  const _InterestItem(this.name, this.icon, this.color);
}
