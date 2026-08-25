import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';

/// One page of a [StepWizard].
///
/// [builder] receives the callback that advances — the step decides when it is
/// satisfied, the wizard decides where "forward" goes.
class WizardStep {
  const WizardStep({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final Widget Function(BuildContext context, VoidCallback onNext) builder;
}

/// The shell shared by registration and social profile completion.
///
/// Owns the header, the progress indicator, the step-info block, the
/// PageController and both directions of movement. It knows nothing about auth
/// state, photos, or what completing means — the two flows differ only in their
/// step list and their [onComplete], which is the whole reason they were two
/// near-identical 500-line widgets before.
class StepWizard extends StatefulWidget {
  const StepWizard({
    super.key,
    required this.steps,
    required this.onComplete,
    this.onExit,
    this.onStepChanged,
    this.isBusy = false,
  });

  final List<WizardStep> steps;

  /// Invoked instead of a page turn when the last step advances. Re-entry is
  /// blocked while it is in flight.
  final Future<void> Function() onComplete;

  /// Back from step 0. Null makes step 0 a dead end with no button.
  final VoidCallback? onExit;

  /// Fires with the new index after every move. The draft save hook.
  final void Function(int step)? onStepChanged;

  /// Drives nothing visually here — steps read it themselves — but is accepted
  /// so a busy flow can be described in one place.
  final bool isBusy;

  @override
  StepWizardState createState() => StepWizardState();
}

/// Public so a host can drive [jumpToStep] through a `GlobalKey`. The draft
/// resume prompt needs exactly that and nothing more.
class StepWizardState extends State<StepWizard> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _completing = false;

  int get currentStep => _currentStep;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Moves straight to [index] with no intermediate animation.
  void jumpToStep(int index) {
    final target = index.clamp(0, widget.steps.length - 1);
    setState(() => _currentStep = target);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
  }

  void _handleNext() {
    if (_currentStep < widget.steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _handleComplete();
  }

  Future<void> _handleComplete() async {
    // A double tap on the final button must not register twice.
    if (_completing) return;
    setState(() => _completing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _handleBack() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    widget.onExit?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AuthGradientScaffold(
      scrollable: false,
      child: Column(
        children: [
          _buildHeader().animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 16),
          _buildProgressIndicator()
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms),
          const SizedBox(height: 24),
          _buildStepInfo()
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideX(begin: -0.1, end: 0, delay: 200.ms, duration: 400.ms),
          const SizedBox(height: 24),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentStep = index);
                widget.onStepChanged?.call(index);
              },
              children: [
                for (final step in widget.steps)
                  step.builder(context, _handleNext),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    // The back affordance is absent, not disabled, when there is nowhere to go.
    final canGoBack = _currentStep > 0 || widget.onExit != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (canGoBack)
            IconButton(
              onPressed: _handleBack,
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
          Text(
            context.l10n.wizardStepCounter(_currentStep + 1, widget.steps.length),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 48), // balances the back button
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final total = widget.steps.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(total, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < total - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepInfo() {
    final step = widget.steps[_currentStep];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.subtitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
