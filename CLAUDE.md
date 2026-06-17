# ידען — Codebase Guide for AI Assistants

## ⚠️ Meta Rule
**After every significant change — update this file.** New feature, renamed key, new screen, bug fix pattern, new gotcha → add it here. This file is the single source of truth that saves tokens in future sessions.

## App Overview
Flutter trivia app (Hebrew, RTL). iOS + Android. Monetized via RevenueCat IAP (Pro tier).
Bundle: `com.shmuelbenhorin.yidaan` | Current version: `1.7.17+62`

## Key Files

### Core
| File | Purpose |
|------|---------|
| `lib/main.dart` | כל המסכים והווידג'טים (~3,823 שורות). מייבא את כל הקבצים למטה |
| `lib/config.dart` | `Cfg` (קבועי משחק, AdMob IDs) + `Pal` (פלטת צבעים) |
| `lib/models/question.dart` | `Diff` enum, `Question` model, `QRepo`, `MistakesService` |

### Services (`lib/services/`)
| File | Class | Purpose |
|------|-------|---------|
| `analytics.dart` | `Analytics` | Firebase Analytics |
| `notification_service.dart` | `NotificationService` | Push notifications (energy + streak) |
| `sfx.dart` | `Sfx` | צלילי משחק + `mutedNotifier` (ValueNotifier) |
| `purchase_service.dart` | `PurchaseService` | RevenueCat IAP |
| `energy_service.dart` | `EnergyService` | מערכת אנרגיה + `checkRecharge()` |
| `level_service.dart` | `LevelService` | כוכבים ושלבים |
| `mistakes_service.dart` | `MistakesService` | שגיאות אחרונות |
| `icloud_kv.dart` | `ICloudKV` | סנכרון iCloud (iOS) |

### Part files (גישה לפרטיים של main.dart)
| File | Purpose |
|------|---------|
| `lib/bagrut_screen.dart` | `part of 'main.dart'` — מסכי בגרות היסטוריה |
| `lib/seasonal_service.dart` | `part of 'main.dart'` — שאלות עונתיות מ-Firestore |

### Other
| File | Purpose |
|------|---------|
| `lib/user_stats.dart` | `UserStatsService` — XP, streak, רמות. `playedToday` getter |
| `lib/interests_service.dart` | `InterestsService` — פילטור קטגוריות |
| `lib/cloud_sync_service.dart` | `CloudSyncService` — Google Drive backup (Android) |
| `lib/leaderboard_service.dart` | `LeaderboardService` — Firebase Anonymous Auth + איסוף נתוני טבלת מובילים |
| `lib/questions_easy/medium/hard.dart` | JSON strings (`kEasy`, `kMedium`, `kHard`) |
| `lib/questions_bagrut.dart` | JSON string (`kBagrut`) |
| `ios/Runner/AppDelegate.swift` | iCloud KV MethodChannel (`icloud_kv`) |
| `codemagic.yaml` | CI/CD — iOS + Android workflows, `xcode: latest` |

## Architecture
- **מסכים וווידג'טים**: ב-`main.dart` (עתידי: להוציא ל-`lib/screens/`)
- **`part of` files**: `bagrut_screen.dart` + `seasonal_service.dart` — גישה למשתנים פרטיים של main.dart
- **State management**: `ChangeNotifier` singletons — `PurchaseService`, `LevelService`, `EnergyService`, `BagrutService`, `UserStatsService`, `SeasonalService`
- **Questions**: Dart `const String` עם JSON משובץ + Firestore (עונתי)
- **Persistence**: `SharedPreferences` בלבד — חוץ מ-seasonal cache
- **Leaderboard**: Firebase Anonymous Auth + Firestore `users/{uid}` — `LeaderboardService.init()` ב-startup, `recordLevel()` ב-`GameState._finish()`
  - Nickname dialog (`_NicknameDialog`) — מוצג בפעם הראשונה בHomeScreen אם `leaderboard_name_set` לא קיים ב-SharedPreferences
  - הכינוי נשמר ב-`leaderboard_display_name` (SharedPreferences) + `users/{uid}.display_name` (Firestore)
  - ⚠️ מסך הטבלה (`LeaderboardScreen`) **לא בנוי עדיין** — יתווסף כשיהיו מספיק שחקנים
  - `fetchTop50()` ו-`fetchMyEntry()` כבר מוכנים ב-leaderboard_service.dart לשימוש עתידי
- **IAP**: RevenueCat (`purchases_flutter`) — entitlement: `'premium'`

## Sound Mute
`Sfx.mutedNotifier` — `ValueNotifier<bool>` נשמר ב-SharedPreferences (`sfx_muted`).
- `Sfx.setMuted(true/false)` — שינוי + שמירה
- `Sfx.muted` — getter נוכחי
- כל correct/wrong/perfect/fail בודקים `if (muted) return;` בתחילה
- הרטט (haptic) **לא** מושתק

## Key Services (all singletons, call `.instance`)
```dart
PurchaseService.instance.isPremium       // Pro check
LevelService.instance.save(diff, idx, stars)
EnergyService.instance.spend(n)
BagrutService.instance.buildPool()       // returns List<BagrutQuestion>
SeasonalService.instance.activeEvents    // List<SeasonalEvent> — filtered by today's date
UserStatsService.instance.playedToday    // bool — whether user already played today
```

## Color Palette (`Pal` class in `lib/config.dart`)
```dart
Pal.bg, Pal.bgD, Pal.card, Pal.cardL
Pal.gold, Pal.accent, Pal.green, Pal.red, Pal.premium
Pal.tp (text primary), Pal.ts (text secondary)
```
Bagrut screens use local constants: `_bg, _card, _gold, _blue, _green, _red, _textP, _textS, _border`

## SharedPreferences Keys
| Key | Type | Purpose |
|-----|------|---------|
| `seen_easy/medium/hard` | StringList | Question IDs already answered correctly |
| `lvl_easy_0`, `lvl_medium_2`, etc. | int | Stars per level (0–3) |
| `energy` | int | Current energy |
| `energy_ts` | int | Timestamp for energy recharge |
| `onboarding_done` | bool | First-run onboarding |
| `levels_completed` | int | For in-app review trigger |
| `mistakes_v2` | StringList | Recent wrong answers (JSON) |
| `bagrut_track` | String | `mamlachti` / `chmd` / `external` |
| `bagrut_onboarded` | bool | Bagrut onboarding done |
| `bagrut_str_{cat}` | int | Topic strength (1=weak, 3=strong) |
| `bagrut_seen_{cat}` | StringList | Correctly answered bagrut question IDs |
| `bagrut_correct/total_{cat}` | int | Per-topic stats |
| `bagrut_dev` | bool | Dev unlock for Bagrut (secret code) |
| `seasonal_events_v1` | String | JSON cache of last fetched seasonal events |

## CRITICAL: Hebrew in JSON strings
**Never use `\"` inside Dart triple-quoted strings (`'''...'''`).** Dart processes `\"` → `"` which breaks JSON parsing silently (no error, just empty question pool).

✅ Use Hebrew gershayim instead: `״` (U+05F4)
- `אצ״ל` not `אצ\"ל`
- `ארה״ב` not `ארה\"ב`
- `תרפ״ט` not `תרפ\"ט`

This applies to ALL question files: `questions_easy/medium/hard/bagrut.dart`

## Question Format
```json
{"id":"q_001","category":"football","d":1,"q":"שאלה?","a":["א","ב","ג","ד"],"c":2,"f":"הסבר"}
```
- `d`: 1=easy, 2=medium, 3=hard
- `c`: correct answer index (0-based)
- `f`: explanation (bagrut only)

Bagrut format adds `"track":["mamlachti","chmd","external"]`

## Seasonal Questions (Firestore — no app update needed)
Managed entirely from Firebase Console. Banner "חם עכשיו 🔥" appears on HomeScreen above difficulty cards when an active event exists.

**Firestore structure:**
```
seasonal_events/{event_id}          ← event metadata
  title:    "מונדיאל 2026 🌍"
  emoji:    "🌍"
  colorHex: "4CAF50"               ← 6-char hex, no #
  from:     Timestamp
  until:    Timestamp
  order:    0                       ← lower = higher on screen
  active:   true

seasonal_events/{event_id}/questions/{q_id}   ← individual questions
  q:        "שאלה?"
  a:        ["א","ב","ג","ד"]
  c:        0
  d:        1
  category: "football"
```

**Key behaviors:**
- Fetched from Firestore on app open (background, non-blocking)
- Cached in `seasonal_events_v1` SharedPreferences for offline use
- `isSeasonal=true` on `GameScreen/GameState` → questions NOT marked as seen in `seen_easy/medium/hard`
- `SeasonalService` is a `ChangeNotifier` — HomeScreen listens and rebuilds when events load

## Push Notifications (NotificationService)
| Channel | ID | Purpose |
|---------|-----|---------|
| `yadaan_energy` | 1 | Energy full — scheduled when energy hits 0 |
| `yadaan_streak` | 3 | Streak reminder — scheduled at 20:00 if user hasn't played today |

**Streak notification logic:**
- Scheduled at app open + every foreground resume
- Cancelled immediately when user answers a question correctly
- Message adapts: 0 days / 1 day / 3+ days / 7+ days

## GameScreen / GameState
```dart
GameScreen(diff: Diff.easy, levelIndex: 0, retryWith: questions, isSeasonal: false)
GameState(levelIdx: 0, diff: Diff.easy, retryWith: questions, isSeasonal: false)
```
- `isSeasonal: true` → skips `QRepo.markSeen()` so seasonal questions stay available

## Streak UI (_StreakPill)
Custom widget replacing `_StatPill` for streak display:
- Emoji 18–22px, number 20–22px bold
- Glow effect when streak ≥ 1, strong glow when streak ≥ 7
- Located in `_UserStatsStrip` on HomeScreen

## PurchaseService — iOS Fix
`purchase()` and `restore()` have two fallback layers:
1. If `entitlements.all['premium']` is inactive → check `entitlements.active.isNotEmpty`
2. If still inactive → wait 800ms, call `syncPurchases()` + `getCustomerInfo()` again
Fixes: Apple charges but app doesn't react (RevenueCat delay / entitlement name mismatch).
**Check RevenueCat Dashboard**: entitlement must be named exactly `premium` (lowercase).

## Bagrut Feature
- **Entry**: pill button on home screen (pulsing gold glow)
- **Gate**: Pro OR `BagrutService.instance.devUnlocked`
- **Tracks**: `mamlachti` (9 topics), `chmd` (17 topics = mamlachti + 8 ancient history), `external` (8 topics)
- **Pool logic**: 70% from weak topics (strength=1), 30% from strong (strength≥2)
- **Onboarding**: chip selection — tap topics to mark as weak, rest = strong
- **Wrong answer**: auto-advance after 900ms (no explanation shown)
- **Correct answer**: manual "next" button + `Sfx.correct()`

## Secret Dev Access
7 rapid taps on "ידען" logo → password dialog → enter `shmuel1231` → unlocks Pro + Bagrut permanently (saved to SharedPreferences `bagrut_dev`).
Defined in `Cfg.devCode`.

## AdMob IDs
- Android App ID: `ca-app-pub-1305167445502870~3867162231`
- iOS Rewarded: `ca-app-pub-1305167445502870/9990640892`
- Android Rewarded: `ca-app-pub-1305167445502870/2554080569`

## iCloud Backup (iOS)
`ICloudKV` class in `main.dart`:
- `saveAll()` — called on app launch + after each level completion
- `restoreIfEmpty()` — called on launch, restores if no local `lvl_` keys exist
- Swift channel: `icloud_kv` in `AppDelegate.swift` using `NSUbiquitousKeyValueStore`

## Android Backup
`allowBackup="true"` in `AndroidManifest.xml` + `backup_rules.xml` + `data_extraction_rules.xml` — auto-syncs SharedPreferences to Google Drive.

## Codemagic Build Notes
- `xcode: latest` (Apple requires iOS 26 SDK as of 2025)
- Must run `flutter config --no-enable-swift-package-manager` before `flutter pub get` (SPM conflicts with `google_mobile_ads` CocoaPods)
- **iOS workflow**: builds IPA → TestFlight (auto)
- **Android workflow**: builds AAB → Google Play internal track (draft). Requires `trivia_keystore` signing + `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` env var

## RTL Rules
- Hebrew screens: wrap top-level widget in `Directionality(textDirection: TextDirection.rtl, child: ...)`
- Mixed number+Hebrew text (e.g. "50 מוחות"): add `textDirection: TextDirection.rtl` on the `Text` widget
- Pure number display: use `textDirection: TextDirection.ltr` to keep number on left
- Arrow icons in RTL: use `Icons.arrow_back_ios_new_rounded` (points right = forward in RTL)

## In-App Review
Triggered at levels_completed = 3, 10, 30 (if score ≥ 50%).
Uses `in_app_review` package. iOS: StoreKit. Android: Play In-App Review API.

## Question Accuracy — Known Fixes Applied
- **מכבי תל אביב** זכתה **5 פעמים** בגביע אירופה: 1977, 1981, 2001, 2004, 2014 (לא 6)
- **נטע ברזילי** זכתה באירוויזיון **2018** (לא 2019) — ישראל אירחה ב-2019
- **יזהר כהן** — זכר → "האמן שייצג" (לא "האמנית")
- **נועה קירל** (לא "נואה קירל") — ייצגה ישראל באירוויזיון 2024, עדן גולן זכתה
- **איסלנד** השתתפה במונדיאל **פעם אחת** בלבד (2018 רוסיה)
