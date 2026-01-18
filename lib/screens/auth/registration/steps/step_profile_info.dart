import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

class StepProfileInfo extends StatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepProfileInfo({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<StepProfileInfo> createState() => _StepProfileInfoState();
}

class _StepProfileInfoState extends State<StepProfileInfo> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late int _selectedAge;
  Gender? _selectedGender;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.data.name;
    _selectedAge = widget.data.age;
    _selectedGender = widget.data.gender == Gender.other ? null : widget.data.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name Field
              _buildLabel('First Name'),
              const SizedBox(height: 8),
              _buildNameField()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Birthday/Age
              _buildLabel('Your Age'),
              const SizedBox(height: 8),
              _buildAgeSelector()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 200.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Gender
              _buildLabel('I am a...'),
              const SizedBox(height: 12),
              _buildGenderSelector()
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 300.ms, duration: 400.ms),

              const SizedBox(height: 32),

              // Continue Button
              _buildContinueButton()
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, delay: 400.ms, duration: 400.ms),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Your first name',
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(Icons.person_outline_rounded, color: Colors.grey[400]),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your name';
        }
        if (value.length < 2) {
          return 'Name must be at least 2 characters';
        }
        return null;
      },
    );
  }

  Widget _buildAgeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_selectedAge years old',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primaryColor,
                    inactiveTrackColor: Colors.grey[300],
                    thumbColor: AppTheme.primaryColor,
                    overlayColor: AppTheme.primaryColor.withOpacity(0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _selectedAge.toDouble(),
                    min: 18,
                    max: 100,
                    divisions: 82,
                    onChanged: (value) {
                      setState(() => _selectedAge = value.round());
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: Gender.values.where((g) => g != Gender.other).map((gender) {
        final isSelected = _selectedGender == gender;
        return GestureDetector(
          onTap: () => setState(() => _selectedGender = gender),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[200]!,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getGenderIcon(gender),
                  color: isSelected ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  gender.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getGenderIcon(Gender gender) {
    switch (gender) {
      case Gender.male:
        return Icons.male_rounded;
      case Gender.female:
        return Icons.female_rounded;
      case Gender.nonBinary:
        return Icons.transgender_rounded;
      default:
        return Icons.person_outline_rounded;
    }
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
    if (_formKey.currentState!.validate()) {
      if (_selectedGender == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select your gender'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }

      widget.data.name = _nameController.text.trim();
      widget.data.age = _selectedAge;
      widget.data.gender = _selectedGender!;
      widget.onNext();
    }
  }
}
