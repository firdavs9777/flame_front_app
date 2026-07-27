import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/profile/edit_profile_screen.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/settings/language_screen.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/config/env.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';

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
          _buildSectionHeader(context.l10n.settingsAccount),
          _buildListTile(
            icon: Icons.person_outline,
            title: 'Edit Profile',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          _buildListTile(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: user?.email ?? 'Not set',
            onTap: () {
              _showChangeEmailDialog(context);
            },
          ),
          // Password self-service (change/forgot) has no backend endpoint yet;
          // gated off with the same flag as forgot-password until it ships.
          if (EnvConfig.current.forgotPasswordEnabled)
            _buildListTile(
              icon: Icons.lock_outline,
              title: 'Change Password',
              onTap: () {
                _showChangePasswordDialog(context, ref);
              },
            ),
          const SizedBox(height: 20),
          _buildSectionHeader('Discovery'),
          _buildSwitchTile(
            icon: Icons.explore_outlined,
            title: 'Discovery',
            subtitle: 'Show me in discovery',
            value: settings.discoveryEnabled,
            onChanged: (_) {
              ref
                  .read(settingsProvider.notifier)
                  .setDiscoveryEnabled(!settings.discoveryEnabled);
            },
          ),
          _buildSwitchTile(
            icon: Icons.location_on_outlined,
            title: 'Show Distance',
            subtitle: 'Show distance on profile',
            value: settings.showDistance,
            onChanged: (_) {
              ref.read(settingsProvider.notifier).toggleShowDistance();
            },
          ),
          _buildSwitchTile(
            icon: Icons.circle_outlined,
            title: 'Show Online Status',
            subtitle: 'Let others know when you\'re online',
            value: settings.showOnlineStatus,
            onChanged: (_) {
              ref.read(settingsProvider.notifier).toggleShowOnlineStatus();
            },
          ),
          const SizedBox(height: 20),

          // Notifications section
          _buildSectionHeader(context.l10n.settingsNotifications),
          _buildSwitchTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            subtitle: 'Get notified about matches and messages',
            value: settings.notificationsEnabled,
            onChanged: (_) {
              ref.read(settingsProvider.notifier).toggleNotifications();
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LanguageScreen()),
              );
            },
          ),

          const SizedBox(height: 20),

          // Appearance section — showcase: kit AppCard + localized theme selector
          _buildSectionHeader(context.l10n.settingsAppearance),
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
          _buildSectionHeader('Legal'),
          _buildListTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () => showLegalDocumentSheet(context, LegalDoc.terms),
          ),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => showLegalDocumentSheet(context, LegalDoc.privacy),
          ),
          _buildListTile(
            icon: Icons.gavel_outlined,
            title: 'Licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Flame',
              applicationVersion: 'v1.0.0',
            ),
          ),

          const SizedBox(height: 20),

          // Danger zone
          _buildSectionHeader('Account Actions'),
          _buildListTile(
            icon: Icons.logout,
            title: context.l10n.settingsLogout,
            titleColor: AppTheme.primaryColor,
            onTap: () {
              _showLogoutDialog(context, ref);
            },
          ),
          _buildListTile(
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
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontWeight: titleColor != null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.grey[700]),
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
            const Text(
              'This action cannot be undone. Enter your password to confirm.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () async {
              final password = passwordController.text;
              if (password.isEmpty) return;
              Navigator.pop(dialogContext);
              final ok = await ref
                  .read(currentUserProvider.notifier)
                  .deleteAccount(password: password);
              if (ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Account deleted')),
                );
                await ref.read(authProvider.notifier).logout();
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Could not delete account. Check your password.'),
                  ),
                );
              }
            },
            child: Text(context.l10n.settingsDelete,
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  void _showChangeEmailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Email'),
        content: const Text('To change your email, please contact support.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
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
                  const SnackBar(
                    content: Text('Password changed successfully'),
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
