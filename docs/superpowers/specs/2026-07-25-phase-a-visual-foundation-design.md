# Phase A: Visual Foundation — Design

**Date:** 2026-07-25
**Status:** Approved for planning
**Scope:** Port BananaTalk's design-system foundation into Flame — a token layer, a reusable UI kit, a complete dark theme with Light/Dark/System selection, a restyled tab bar, and 5 new languages. Foundation only: existing screens keep working; only two showcase screens are migrated.

## Background

Flame is a mature Flutter dating app (Riverpod + go_router + socket.io chat + i18n). The BananaTalk language-exchange app shares the same stack and ships a polished design-system foundation Flame lacks. This phase ports that foundation, adapted to Flame's own coral/fire identity, without adopting BananaTalk's visual look or its backend-coupled features (those are deferred to later phases: B = tap-to-translate + voice messages; C = stories).

### Current state (verified in code)

- **Theme** (`lib/theme/app_theme.dart`): flat static colors + `lightTheme`/`darkTheme` getters. The dark theme is a **stub** — it defines only appBar/card/bottomNav and omits the button, input, and text themes the light theme has. No design-token layer (no typography/radius/shadow/spacing scales).
- **Theme mode**: `AppSettings.isDarkMode` is a plain `bool` (`lib/providers/settings_provider.dart`); `main.dart` maps it to `ThemeMode.dark`/`.light`. No "follow system" option. Settings are **not persisted** at all.
- **Widgets** (`lib/widgets/`): only 3 ad-hoc widgets (`action_buttons`, `profile_card`, `smart_image`). No reusable kit.
- **Tab bar** (`lib/screens/main_shell.dart`): a plain Material `BottomNavigationBar`, 4 tabs (Discover / Chat / Profile / Settings) in an `IndexedStack`, with an inline unread badge.
- **i18n**: complete infra (`lib/core/i18n/`, `lib/l10n/`), 7 ARB files (en, es, pt_BR, fr, de, ru), ~79 keys. Locales are registered in `kSupportedLocales` + `displayNameOf` (`supported_locales.dart`); the language picker auto-iterates them.

### BananaTalk source (reference, read-only)

`/Users/firdavsmutalipov/Projects/BananaTalk/bananatalk_app/lib/core/`:
- `theme/app_theme.dart` (735 lines) — token classes: `AppColors` (light/dark pairs), `AppTypography`, `AppRadius`, `AppShadows`, `AppSpacing`.
- `widgets/` — `app_button`, `app_card`, `app_input`, `app_avatar`, `app_badge`, `app_loading` (~1,700 lines). Only external dep is `cached_network_image` (already in Flame's pubspec). Widgets reference the token classes above (e.g. `AppTypography.buttonMedium`, `AppColors.cardDark`, `AppRadius.borderLG`, `AppShadows.sm`, `AppSpacing.cardPadding`).

## Goals

1. A design-token layer adapted to Flame's coral identity (`#FF6B6B` primary, `#FF8E8E` secondary, `#FFE66D` accent).
2. A reusable 6-widget UI kit built on those tokens, theme-aware in light and dark.
3. A **complete** dark theme at parity with light, selectable as Light / Dark / **System**, persisted across launches.
4. A restyled, animated tab bar consistent with the kit.
5. Five new languages: **ja, ko, zh, tr, id**.
6. Prove the kit end-to-end by migrating exactly two screens (Settings, Login).

### Non-goals (explicitly deferred)

- Migrating any screen other than Settings and Login.
- Adopting BananaTalk's visual look — Flame keeps its own palette/identity.
- Right-to-left (Arabic) support — not in the +5 set.
- Any Phase B/C feature (tap-to-translate, voice messages, stories).
- Persisting settings other than theme mode (only `themeMode` gains persistence here).

## Design

### 1. Design tokens (`lib/theme/`)

Extend the theme **in place** (keeping `lib/theme/app_theme.dart` as the import path so no app-wide import churn) with token classes, ported from BananaTalk and recolored to Flame:

- `AppColors` — light **and** dark values for `background`, `surface`, `card`, `textPrimary`, `textSecondary`, `border`, plus semantic `success`/`error`/`warning`. Primary/secondary/accent stay Flame's coral set.
- `AppTypography` — the text-style scale including `buttonSmall`/`buttonMedium`/`buttonLarge` (required by `AppButton`).
- `AppRadius` — `sm`/`md`/`lg`/`xl` `BorderRadius` constants (kit uses `borderLG`).
- `AppShadows` — `sm`/`md`/`lg` `List<BoxShadow>`.
- `AppSpacing` — spacing scale + `cardPadding`.
- `AppTheme.lightTheme` / `darkTheme` — rebuilt on the tokens so **dark reaches full parity**: button, input, and text themes are defined for dark, matching light.

The token API names must match what the ported kit references so the port is mechanical.

### 2. UI kit (`lib/widgets/kit/`)

Port six widgets, rewired from BananaTalk's tokens to Flame's:

- `AppButton` — variants `primary`/`secondary`/`outline`/`ghost`/`danger` × sizes `small`/`medium`/`large`; supports `icon`, `suffixIcon`, `isLoading`, `isFullWidth`, `isDisabled`.
- `AppCard` — padding/margin/color/radius/shadow/border overrides, optional `onTap`/`onLongPress`, theme-aware card color.
- `AppInput` — themed text field consistent with `inputDecorationTheme`.
- `AppAvatar` — network image via `cached_network_image`, with fallback/initials.
- `AppBadge` — count/dot badge (the tab-bar unread badge is refactored onto this).
- `AppLoading` — themed loading indicator/skeleton.

Location `lib/widgets/kit/` sits alongside existing `lib/widgets/` and keeps kit separate from feature widgets. Barrel file `lib/widgets/kit/kit.dart` re-exports all six.

### 3. Theme mode: Light / Dark / System

- Replace `AppSettings.isDarkMode` (bool) with `themeMode` (`ThemeMode`, default `system`).
- Persist `themeMode` via `shared_preferences` (already a dep); `SettingsNotifier` loads it on construction and writes on change. Other `AppSettings` fields are unchanged (still in-memory).
- `main.dart`: `themeMode: settings.themeMode`.
- Settings screen: replace the dark-mode toggle with a 3-way selector (System / Light / Dark). Labels are new localized strings.
- Migration: any previously-stored bool is irrelevant (settings weren't persisted), so default is simply `system`.

### 4. Tab bar restyle (`lib/screens/main_shell.dart`)

Rebuild the bottom nav using tokens: coral active indicator, animated icon transition on tab change (`flutter_animate`, already a dep), unread badge refactored to `AppBadge`. Keep the 4 tabs, `IndexedStack`, and `bottomNavIndexProvider` behavior — **visual change only**.

### 5. New languages (ja, ko, zh, tr, id)

- Add `app_ja.arb`, `app_ko.arb`, `app_zh.arb`, `app_tr.arb`, `app_id.arb` with all ~79 existing keys **plus** the new Phase A keys, translated.
- Register each in `kSupportedLocales` and add a `displayNameOf` case (日本語, 한국어, 中文, Türkçe, Bahasa Indonesia).
- Run `gen-l10n`; the language picker auto-lists them.

### 6. New/updated localized strings

Every new user-facing string introduced by Phase A (theme selector labels: "System"/"Light"/"Dark" + section title; any kit-related copy) is added to **all 12** ARB files (7 existing + 5 new) so key parity holds. No hardcoded strings in new UI.

### 7. Showcase migration

Migrate exactly two screens to the kit to prove it end-to-end, then stop:
- `settings_screen.dart` — uses `AppCard`, `AppButton`, the theme selector.
- `login_screen.dart` — uses `AppInput`, `AppButton`.

All other screens are untouched and keep compiling against the unchanged theme.

## Testing

- **Kit widgets**: render without error in both light and dark themes; `AppButton` variant × size matrix renders; `AppBadge` count/dot states.
- **Theme mode**: switching the `themeMode` setting propagates to `MaterialApp.themeMode`; `system` follows platform brightness; selection persists across a `SettingsNotifier` reload.
- **Tab bar**: renders 4 tabs, tab tap updates `bottomNavIndexProvider`, unread badge shows when count > 0.
- **i18n**: existing ARB-key-parity test extended to the 5 new locales (all 12 ARBs share the same key set, including the new Phase A keys).

## Risks & mitigations

- **Token-name drift** between Flame tokens and the ported kit → define tokens first, matching BananaTalk's names, then port widgets against them.
- **Translation quality** for 5 new languages → generated during implementation; native review can follow later (out of scope for correctness here — parity + rendering are what's tested).
- **Dark-theme regressions** on unmigrated screens → dark theme only *adds* previously-missing definitions; existing light behavior is preserved; showcase screens verify the kit in both modes.

## Rollout

Single feature branch. Order: (1) tokens + complete dark theme, (2) UI kit, (3) theme-mode setting + persistence, (4) tab bar restyle, (5) new locales + Phase A strings, (6) showcase migration, (7) tests. Each is independently reviewable; details in the implementation plan.
