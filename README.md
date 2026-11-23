<p align="center">
  <img src="branding/logo.png" alt="Taxi Logbuch logo" width="120">
</p>

<h1 align="center">Taxi Logbuch</h1>

<p align="center">
  A Flutter app that helps taxi drivers track their fares, shifts and earnings in one place.<br>
  <b>Flutter · Dart · Firebase Auth · Cloud Firestore · PDF reports · GitHub Actions</b>
</p>

---

## The problem

Taxi drivers in Germany often work for several platforms at once: classic taxi rides, Uber, Bolt, FREENOW, plus cash and card payments. At the end of a shift they usually don't know exactly:

- how much they earned today, this week and this month,
- how much came in as **cash** versus through a **platform**,
- how many hours they actually worked after breaks,
- what their **average per day** is.

**Taxi Logbuch** answers these questions. Drivers enter each fare in a few taps and get daily and monthly statistics plus a printable monthly PDF report.

## Features

**Fares**
- Enter a fare amount in cents (`2270` becomes `22,70 €`), so there are no rounding errors
- Fare **source** (Taxi, Uber, Bolt, FREENOW, custom) is stored separately from **payment method** (cash, card, invoice, via platform), and combinations such as *Uber + cash* are supported
- Optional tip, distance and note for each fare
- Edit and soft-delete fares with a change history, so deleted fares no longer count toward revenue

**Shifts & breaks**
- Start and stop shifts and breaks with a timer, or enter them manually
- Night shifts are split correctly at midnight, and overlapping intervals are counted only once
- Working-time warnings (over 8 h, 10 h and 12 h) based on the German Working Hours Act (ArbZG)

**Statistics & reports**
- Daily revenue, cash share, monthly revenue and average per working day
- Weekly comparison and an optional daily goal
- Filters by day, source and payment method
- Cash count and expense tracking (*Extras*)
- **Monthly PDF report** ready to print or share

**Accounts & app**
- Email/password registration, login, password reset and password change
- Each driver can access only their own data, enforced by Firestore security rules
- Account deletion, privacy policy and imprint (GDPR-ready)
- 5 languages: German, English, Persian, Turkish and Arabic (including right-to-left layout)
- Light and dark theme
- Installable as a web app (PWA) on Android and iPhone, with an in-app install guide and a QR code card

## Tech stack

| Area | Technology |
|---|---|
| UI | Flutter (Material 3), custom theme, `intl` localization |
| State | `ChangeNotifier`-based stores (`LogbookStore`, `CloudLogbookStore`) |
| Backend | Firebase Authentication, Cloud Firestore |
| Offline | `shared_preferences` for local data; Firestore offline writes |
| Reports | `pdf` and `printing` packages |
| Quality | `flutter_lints`, 13 test files (unit and widget tests) |
| CI/CD | GitHub Actions: analyze → test → live Firestore rule check → web build → Firebase Hosting deploy |

## Architecture

```
lib/
├── main.dart            App shell, navigation (Fares · Shifts · Month · Profile)
├── logbook.dart         Domain model: Trip, PaymentMethod, revenue and summary logic
├── shifts.dart          Shifts, interval merging, working-time totals
├── pauses.dart          Break records
├── store.dart           LogbookStore (ChangeNotifier), local persistence
├── cloud_store.dart     Firestore backend behind the UserLogbookBackend interface
├── auth_service.dart    DriverAuth interface + FirebaseDriverAuth implementation
├── pdf_report.dart      Monthly PDF report
├── l10n*.dart           Translations (de, en, fa, tr, ar)
└── *_screen.dart        UI screens (auth, help, install, legal, pauses …)
```

```
 UI (Widgets) ──listens──▶ LogbookStore (ChangeNotifier)
                               │
                               ▼
                     UserLogbookBackend (interface)
                               │
                 ┌─────────────┴─────────────┐
                 ▼                           ▼
        Local storage               FirestoreLogbookBackend
     (shared_preferences)       users/{uid}/trips|shifts|pauses
```

- **The business logic is pure Dart** (`logbook.dart`, `shifts.dart`) and has no Flutter dependency, which makes it easy to unit-test.
- **Backends sit behind interfaces** (`UserLogbookBackend`, `DriverAuth`), so tests can use fakes instead of Firebase.
- **Money is stored as integer cents**, never as a `double`.
- **Security rules** allow only known paths and validate field names, types and sizes. CI checks them against the real Firebase project using two temporary accounts.

## Screenshots

| Fares | Shifts | Month | PDF report |
|---|---|---|---|
| _coming soon_ | _coming soon_ | _coming soon_ | _coming soon_ |

## Getting started

Requires Flutter **3.35.7**.

```bash
bash tool/bootstrap.sh     # creates missing android/ and web/ folders
flutter pub get
flutter run -d chrome
```

Run checks:

```bash
flutter analyze
flutter test
flutter build web --release
```

Firebase setup and detailed developer notes (in German): [`config/README.md`](config/README.md) and [`docs/DEVELOPMENT.de.md`](docs/DEVELOPMENT.de.md).

## Roadmap

- GPS-based automatic shift and break detection
- Native Android release (Play Store)
- Push reminders for shift start and end

## Author

**Reza Tajalli**, Mobile App Developer (Flutter · Android · iOS), Berlin
