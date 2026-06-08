# ידען — Codebase Guide for AI Assistants

## ⚠️ Meta Rule
**After every significant change — update this file.** New feature, renamed key, new screen, bug fix pattern, new gotcha → add it here. This file is the single source of truth that saves tokens in future sessions.

## App Overview
Flutter trivia app (Hebrew, RTL). iOS + Android. Monetized via RevenueCat IAP (Pro tier).
Bundle: `com.shmuelbenhorin.yidaan` | Current version: `1.7.14+55`

## Key Files
| File | Purpose |
|------|---------|
| `lib/main.dart` | Everything — all screens, services, logic. Also pulls in `bagrut_screen.dart` via `part` |
| `lib/bagrut_screen.dart` | `part of 'main.dart'` — full Bagrut history quiz feature |
| `lib/questions_easy/medium/hard.dart` | JSON strings (`kEasy`, `kMedium`, `kHard`) — trivia questions |
| `lib/questions_bagrut.dart` | JSON string (`kBagrut`) — history exam questions |
| `lib/user_stats.dart` | XP, streaks, levels |
| `lib/interests_service.dart` | Category interest filtering |
| `ios/Runner/AppDelegate.swift` | iCloud KV Store MethodChannel (`icloud_kv`) |
| `ios/Runner/Runner.entitlements` | iCloud KV entitlement |
| `android/app/src/main/AndroidManifest.xml` | Auto Backup config |
| `codemagic.yaml` | CI/CD — uses `xcode: latest`, disables SPM before pub get |

## Architecture
- **No separate files per screen** — everything in `main.dart` (+ `bagrut_screen.dart` as a `part`)
- **State management**: `ChangeNotifier` singletons — `PurchaseService`, `LevelService`, `EnergyService`, `BagrutService`, `UserStatsService`
- **Questions**: Dart `const String` with embedded JSON, parsed at runtime via `jsonDecode`
- **Persistence**: `SharedPreferences` only (no database, no server)
- **IAP**: RevenueCat (`purchases_flutter`) — entitlement: `'premium'`

## Key Services (all singletons, call `.instance`)
```dart
PurchaseService.instance.isPremium   // Pro check
LevelService.instance.save(diff, idx, stars)
EnergyService.instance.spend(n)
BagrutService.instance.buildPool()   // returns List<BagrutQuestion>
```

## Color Palette (`Pal` class in main.dart)
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

## RTL Rules
- Hebrew screens: wrap top-level widget in `Directionality(textDirection: TextDirection.rtl, child: ...)`
- Mixed number+Hebrew text (e.g. "50 מוחות"): add `textDirection: TextDirection.rtl` on the `Text` widget
- Pure number display: use `textDirection: TextDirection.ltr` to keep number on left
- Arrow icons in RTL: use `Icons.arrow_back_ios_new_rounded` (points right = forward in RTL)

## In-App Review
Triggered at levels_completed = 3, 10, 30 (if score ≥ 50%).
Uses `in_app_review` package. iOS: StoreKit. Android: Play In-App Review API.
