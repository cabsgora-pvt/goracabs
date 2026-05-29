import 'package:flutter/material.dart';
import '../features/splash/splash_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/auth/pages/login_page.dart';
import '../features/auth/pages/otp_page.dart';
import '../features/auth/pages/driver_otp_page.dart';
import '../features/home/pages/home_page.dart';
import '../features/registration/personal_details_page.dart';
import '../features/registration/vehicle_selection_page.dart';
import '../features/registration/vehicle_details_page.dart';
import '../features/registration/document_upload_page.dart';
import '../features/registration/bank_details_page.dart';
import '../features/registration/kyc_success_page.dart';
import '../features/registration/kyc_pending_page.dart';
import '../features/registration/rejection_page.dart';
import '../features/ride/pages/incoming_ride_page.dart';
import '../features/ride/pages/on_ride_page.dart';
import '../features/ride/pages/invoice_page.dart';
import '../features/ride/pages/review_page.dart';
import '../features/earnings/pages/earnings_page.dart';
import '../features/history/pages/history_page.dart';
import '../features/wallet/pages/wallet_page.dart';
import '../features/notifications/pages/notification_page.dart';
import '../features/account/pages/account_page.dart';
import '../features/account/pages/profile_page.dart';
import '../features/account/pages/leaderboard_page.dart';
import '../features/account/pages/incentive_page.dart';
import '../features/account/pages/sos_page.dart';
import '../features/account/pages/documents_page.dart';
import '../features/account/pages/settings_page.dart';
import '../features/account/pages/support_page.dart';
import '../features/account/pages/faq_page.dart';
import '../features/account/pages/preferences_page.dart';
import '../features/account/pages/misc_pages.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> get routes => {
    SplashPage.route:              (_) => const SplashPage(),
    OnboardingPage.route:          (_) => const OnboardingPage(),
    LoginPage.route:               (_) => const LoginPage(),
    OtpPage.route:                 (_) => const OtpPage(),
    DriverOtpPage.route:           (_) => const DriverOtpPage(),
    HomePage.route:                (_) => const HomePage(),
    PersonalDetailsPage.route:     (_) => const PersonalDetailsPage(),
    VehicleSelectionPage.route:    (_) => const VehicleSelectionPage(),
    VehicleDetailsPage.route:      (_) => const VehicleDetailsPage(),
    DocumentUploadPage.route:      (_) => const DocumentUploadPage(),
    BankDetailsPage.route:         (_) => const BankDetailsPage(),
    KycSuccessPage.route:          (_) => const KycSuccessPage(),
    KycPendingPage.route:          (_) => const KycPendingPage(),
    RejectionPage.route:           (_) => const RejectionPage(),
    IncomingRidePage.route:   (_) => const IncomingRidePage(),
    OnRidePage.route:         (_) => const OnRidePage(),
    InvoicePage.route:        (_) => const InvoicePage(),
    ReviewPage.route:         (_) => const ReviewPage(),
    EarningsPage.route:       (_) => const EarningsPage(),
    HistoryPage.route:        (_) => const HistoryPage(),
    WalletPage.route:         (_) => const WalletPage(),
    NotificationPage.route:   (_) => const NotificationPage(),
    ProfilePage.route:        (_) => const ProfilePage(),
    LeaderboardPage.route:    (_) => const LeaderboardPage(),
    IncentivePage.route:      (_) => const IncentivePage(),
    SosPage.route:            (_) => const SosPage(),
    DocumentsPage.route:      (_) => const DocumentsPage(),
    SettingsPage.route:       (_) => const SettingsPage(),
    SupportPage.route:        (_) => const SupportPage(),
    FaqPage.route:            (_) => const FaqPage(),
    PreferencesPage.route:    (_) => const PreferencesPage(),
    QrCodePage.route:         (_) => const QrCodePage(),
    RateCardPage.route:       (_) => const RateCardPage(),
    ReferralPage.route:       (_) => const ReferralPage(),
    DriverLevelsPage.route:   (_) => const DriverLevelsPage(),
    RewardsPage.route:        (_) => const RewardsPage(),
    ReportsPage.route:        (_) => const ReportsPage(),
    AdminChatPage.route:      (_) => const AdminChatPage(),
    SubscriptionPage.route:   (_) => const SubscriptionPage(),
    VehicleInfoPage.route:    (_) => const VehicleInfoPage(),
  };
}
