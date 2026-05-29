# Gora Driver App 🚖

A complete Flutter driver app with **Blue + White** premium UI and **mock backend** (no real API needed).

## 🚀 Quick Start

```bash
cd gora_driver
flutter pub get
flutter run
```

## 🔐 Demo Login
- **Phone:** any 10-digit number
- **OTP:** `1234`

## 📱 All Pages (31 routes)

| Flow | Pages |
|------|-------|
| Launch | Splash → Onboarding → Login |
| Auth | Login → OTP Verify |
| Main | Home (Map) → Earnings → Account |
| Ride | Incoming Request → On Ride → Invoice → Review |
| Account | Profile, Vehicle, Documents, QR Code |
| Earnings | Weekly Chart + Daily Breakdown |
| History | Trip List → Trip Detail |
| Wallet | Balance + Transactions → Withdraw |
| Rewards | Incentives, Leaderboard, Levels, Rewards |
| Support | SOS, Admin Chat, Support Tickets, FAQ |
| Settings | Preferences, Settings, FAQ |

## 🎨 Theme
- Primary: `#1565C0` (Deep Blue)
- Background: `#FFFFFF` (White)
- Cards: `#F0F4FF` (Soft Blue-White)

## 🏗️ Architecture

```
lib/
├── main.dart
├── app/             ← Routes + App widget
├── core/            ← Theme, Colors, Widgets
├── models/          ← Data models
├── mock/            ← Mock services (fake API with Future.delayed)
└── features/
    ├── auth/        ← Login, OTP
    ├── splash/      ← Splash screen
    ├── onboarding/  ← 3-slide onboarding
    ├── home/        ← Map home screen
    ├── ride/        ← Full ride flow
    ├── earnings/    ← Chart + stats
    ├── history/     ← Trip history
    ├── wallet/      ← Wallet + withdraw
    ├── notifications/
    └── account/     ← All account pages
```

## 🔄 Switching to Real Backend
Replace `mock/mock_data.dart` services with real API calls.
The BLoC layer and UI stay exactly the same — just swap:
```dart
// Before (mock)
static Future<DriverModel> getProfile() => mockFetch(mockDriver);

// After (real)
static Future<DriverModel> getProfile() => ApiService.get('/driver/profile');
```
