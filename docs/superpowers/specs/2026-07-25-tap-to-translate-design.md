# Tap-to-Translate (Chat) — Design

**Date:** 2026-07-25
**Status:** Implemented (frontend); backend endpoint pending
**Scope:** Inline tap-to-translate for incoming chat text messages. A lean port of BananaTalk's translation UX, adapted to Flame's architecture.

## Background

Flame is now multilingual (11 UI locales) and matches will chat across languages, so translating a partner's messages is high-value. BananaTalk has a rich translation stack (AI breakdown, transliteration, TTS, vocabulary save, per-user quota, a tap-to-expand bottom sheet, three cache layers). Flame does **not** need that depth yet, and — importantly — Flame's backend has **no** translation endpoint. This phase builds the client seam and the inline UX so the feature works end-to-end in the app the moment a `/translate` endpoint ships.

## Decision: backend approach

Flame's backend doesn't have translation yet. Rather than couple to a third-party provider + API key from the client, this uses **a new endpoint on Flame's own API** (`POST /translate`), consistent with the existing `ApiClient`/`ServiceResult` conventions. All translation logic (provider choice, caching, quota) lives server-side behind that seam, so the client never changes when the provider is decided. Until the endpoint is live, the UI degrades gracefully ("Translation unavailable").

## Design

**`TranslationService`** (`lib/services/translation_service.dart`)
- `Future<ServiceResult<String>> translate({required String text, required String targetLang, String? sourceLang})`.
- POSTs `{text, target_lang, source_lang?}` to `/translate` via `ApiClient`.
- Reads the translated string defensively from `translated_text` / `translation` / `text`, so a backend key change won't break the client.
- Constructor takes an optional `ApiClient` for test injection; empty text short-circuits without a network call.

**`translationProvider`** (`lib/providers/translation_provider.dart`)
- `StateNotifier<Map<String messageId, TranslationEntry>>`; `TranslationEntry { status: idle|loading|done|error, text?, visible }`.
- `toggle({messageId, text, targetLang})`: translates on first use; on an already-translated message it flips `visible` without re-fetching. The map is the process-level cache (mirrors BananaTalk's static widget cache).

**Inline UI** (`_TranslateSection` in `message_bubble.dart`)
- Shown only under **incoming** (`!isMe`), non-empty text messages.
- A "Translate" affordance (translate icon + label). Tapping translates; when shown, the label becomes "Hide translation".
- States: loading (spinner + "Translating…"), done (translated text under the original), error ("Translation unavailable").
- Target language = the app locale (`localeProvider.languageCode`), fallback `en`. Source language is left to backend auto-detect.
- Strings localized across all 12 ARBs: `chatTranslate`, `chatHideTranslation`, `chatTranslating`, `chatTranslationUnavailable`.

## Non-goals (vs BananaTalk)

- No AI word breakdown, transliteration, alternatives, grammar/idiom/cultural notes.
- No tap-to-expand bottom sheet, TTS, or save-to-vocabulary.
- No per-user quota / VIP paywall, no per-conversation auto-translate toggle.
- No manual language picker (uses the app locale).

These are deferred; the service/provider seam leaves room to grow into them.

## Testing

- `TranslationService`: success (data envelope + bare key), 404 → graceful failure, empty text → no network. Injected mock `ApiClient`.
- `translationProvider`: stores translation + visible on success; second toggle hides without refetch; failure → error state.
- ARB parity test already covers the 4 new keys across all 12 locales.

## Risks

- **No backend yet** → the UI shows "Translation unavailable" until `/translate` exists; nothing crashes.
- **Auth/URL** → uses the authenticated `ApiClient`, so the endpoint inherits the app's bearer-token handling.
