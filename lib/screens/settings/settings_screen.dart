import 'package:flame/core/navigation/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/config/env.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';
import 'package:flame/screens/settings/widgets/settings_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final userState = ref.watch(currentUserProvider);
    final user = userState.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader(context, context.l10n.settingsAccount),
          // No Edit Profile row: Settings is reached FROM Profile now, so
          // pointing back at it is a loop.
          _buildListTile(
            context: context,
            icon: Icons.email_outlined,
            title: context.l10n.settingsEmail,
            subtitle: user?.email ?? 'Not set',
            onTap: () {
              _showChangeEmailDialog(context);
            },
          ),
          // Password self-service (change/forgot) has no backend endpoint yet;
          // gated off with the same flag as forgot-password until it ships.
          if (EnvConfig.current.forgotPasswordEnabled)
            _buildListTile(
              context: context,
              icon: Icons.lock_outline,
              title: context.l10n.settingsChangePassword,
              onTap: () {
                _showChangePasswordDialog(context, ref);
              },
            ),
          const SizedBox(height: 20),
          _buildSectionHeader(context, 'Privacy & Safety'),
          _buildListTile(
            context: context,
            icon: Icons.block,
            title: context.l10n.settingsBlockedUsers,
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.blockedUsers,
              );
            },
          ),
          // One control, one path. This switch and the one in Edit Profile →
          // Preferences now both read the stored preference off the current
          // user and both write through `updatePreferences`, so they cannot
          // disagree. It previously pointed at `settingsProvider`, which
          // mutated in-memory state and issued no request at all.
          //
          // Disabled rather than hidden while the user is loading: hiding it
          // would reflow the list, and a switch that is visibly inert is
          // honest about not knowing the value yet.
          _buildSwitchTile(
            key: const Key('settings_show_online_switch'),
            context: context,
            icon: Icons.circle_outlined,
            title: context.l10n.settingsShowOnlineStatus,
            subtitle: context.l10n.settingsShowOnlineStatusSubtitle,
            value: user?.showOnlineStatus ?? true,
            onChanged: user == null
                ? null
                : (value) => _setShowOnlineStatus(context, ref, value),
          ),
          // Scope A made distance real and taught the server to honour
          // preferences.showDistance, but shipped no way to exercise it. Same
          // disabled-while-loading contract as the switch above.
          _buildSwitchTile(
            key: const Key('settings_show_distance_switch'),
            context: context,
            icon: Icons.social_distance_outlined,
            title: context.l10n.settingsShowDistance,
            subtitle: context.l10n.settingsShowDistanceSubtitle,
            value: user?.showDistance ?? true,
            onChanged: user == null
                ? null
                : (value) => _setShowDistance(context, ref, value),
          ),
          const SizedBox(height: 20),

          // Notifications section
          _buildSectionHeader(context, context.l10n.settingsNotifications),
          _buildListTile(
            context: context,
            icon: Icons.notifications_outlined,
            title: context.l10n.settingsNotifications,
            subtitle: context.l10n.settingsNotificationsSubtitle,
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.notificationSettings,
              );
            },
          ),

          // Language entry
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(context.l10n.settingsLanguage),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayNameOf(ref.watch(localeProvider) ?? const Locale('en'))),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              Navigator.of(context).pushNamed(
                AppRoutes.language,
              );
            },
          ),

          const SizedBox(height: 20),

          // Appearance section — showcase: kit AppCard + localized theme selector
          _buildSectionHeader(context, context.l10n.settingsAppearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.dark_mode_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          context.l10n.settingsTheme,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: settings.themeMode,
                    onChanged: _onThemeModeChanged(ref),
                    title: Text(context.l10n.themeSystem),
                    secondary: const Icon(Icons.brightness_auto_outlined),
                    activeColor: AppTheme.primaryColor,
                    dense: true,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: settings.themeMode,
                    onChanged: _onThemeModeChanged(ref),
                    title: Text(context.l10n.themeLight),
                    secondary: const Icon(Icons.light_mode_outlined),
                    activeColor: AppTheme.primaryColor,
                    dense: true,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: settings.themeMode,
                    onChanged: _onThemeModeChanged(ref),
                    title: Text(context.l10n.themeDark),
                    secondary: const Icon(Icons.dark_mode_outlined),
                    activeColor: AppTheme.primaryColor,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Legal section
          _buildSectionHeader(context, 'Legal'),
          _buildListTile(
            context: context,
            icon: Icons.description_outlined,
            title: context.l10n.settingsTermsOfService,
            onTap: () => showLegalDocumentSheet(context, LegalDoc.terms),
          ),
          _buildListTile(
            context: context,
            icon: Icons.privacy_tip_outlined,
            title: context.l10n.settingsPrivacyPolicy,
            onTap: () => showLegalDocumentSheet(context, LegalDoc.privacy),
          ),
          _buildListTile(
            context: context,
            icon: Icons.gavel_outlined,
            title: context.l10n.settingsLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Flame',
              applicationVersion: 'v1.0.0',
            ),
          ),

          const SizedBox(height: 20),

          // Danger zone
          _buildSectionHeader(context, 'Account Actions'),
          _buildListTile(
            context: context,
            icon: Icons.logout,
            title: context.l10n.settingsLogout,
            titleColor: AppTheme.primaryColor,
            onTap: () {
              _showLogoutDialog(context, ref);
            },
          ),
          _buildListTile(
            context: context,
            icon: Icons.delete_outline,
            title: context.l10n.settingsDeleteAccount,
            titleColor: AppTheme.errorColor,
            onTap: () {
              _showDeleteAccountDialog(context, ref);
            },
          ),

          const SizedBox(height: 40),

          // App version
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Flame v1.0.0',
                  style: TextStyle(color: context.secondaryText, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  ValueChanged<ThemeMode?> _onThemeModeChanged(WidgetRef ref) {
    return (mode) {
      if (mode != null) {
        ref.read(settingsProvider.notifier).setThemeMode(mode);
      }
    };
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.secondaryText,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    // Delegates to SettingsRow rather than building a ListTile, so text scaling,
    // tap targets and the wide-window constraint are decided in one place for all
    // twenty call sites instead of here and in _buildSwitchTile separately.
    //
    // titleColor is still honoured because the destructive rows (delete account)
    // depend on it, so this is a routing change and not a restyle.
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, color: titleColor ?? context.secondaryText),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
      titleColor: titleColor,
    );
  }

  /// Writes "show online status" through the same server-backed path the Edit
  /// Profile control uses. On failure the notifier leaves state alone, so the
  /// switch snaps back on its own — the SnackBar is there so that snap-back
  /// reads as a failed save rather than an unresponsive control.

  /// Writes preferences.showDistance.
  ///
  /// On failure the switch reverts, because the control reflects server state
  /// rather than intent — one that stays flipped after a refusal is lying.
  Future<void> _setShowDistance(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final ok = await ref
        .read(currentUserProvider.notifier)
        .updatePreferences(showDistance: value);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed)));
    }
  }

  Future<void> _setShowOnlineStatus(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(currentUserProvider.notifier)
        .updatePreferences(showOnlineStatus: value);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.settingsSaveFailed)),
      );
    }
  }

  Widget _buildSwitchTile({
    Key? key,
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      key: key,
      secondary: Icon(icon, color: context.secondaryText),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      activeColor: AppTheme.primaryColor,
      onChanged: onChanged,
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsLogoutConfirmTitle),
        content: Text(context.l10n.settingsLogoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: Text(
              context.l10n.settingsLogout,
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    // A social-only signup has no password to confirm with. Demanding one made
    // the account deletion Google Play requires unreachable for every Google
    // user — and Google is the only social provider live in prod.
    final hasPassword =
        ref.read(currentUserProvider).valueOrNull?.hasPassword ?? true;
    final passwordController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.settingsDeleteAccount),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Was a hardcoded English sentence. The password field below is
            // labelled, so one localised line covers both cases.
            Text(context.l10n.settingsDeleteAccountBody),
            if (hasPassword) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('delete_account_password'),
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsPassword,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.settingsCancel),
          ),
          TextButton(
            key: const Key('delete_account_confirm'),
            onPressed: () async {
              final password = passwordController.text;
              // Only a password account can be blocked on an empty box; for a
              // social one there is nothing to type and nothing to wait for.
              if (hasPassword && password.isEmpty) return;
              Navigator.pop(dialogContext);
              final ok = await ref
                  .read(currentUserProvider.notifier)
                  .deleteAccount(password: hasPassword ? password : null);
              if (ok) {
                messenger.showSnackBar(
                  SnackBar(content: Text(context.l10n.settingsAccountDeleted)),
                );
                await ref.read(authProvider.notifier).logout();
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.settingsAccountDeleteFailed),
                  ),
                );
              }
            },
            child: Text(context.l10n.settingsDelete),
          ),
        ],
      ),
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsChangeEmail),
        content: Text(context.l10n.settingsChangeEmailContactSupport),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonOk),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsChangePassword),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsCurrentPassword,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsNewPassword,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsConfirmNewPassword,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.settingsPasswordsDoNotMatch)),
                );
                return;
              }
              Navigator.pop(context);
              final success = await ref
                  .read(authProvider.notifier)
                  .changePassword(
                    currentPassword: currentPasswordController.text,
                    newPassword: newPasswordController.text,
                  );
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.settingsPasswordChanged),
                  ),
                );
              }
            },
            child: Text(
              'Change',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
