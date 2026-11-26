/// This build's version, compared with the server's force-update settings
/// (GET /api/app-config?app=driver → config.version).
///
/// Must match `version:` in pubspec.yaml (without the +build) — a test fails
/// when they differ, so a release cannot ship with the wrong number.
const appVersion = '1.5.0';

/// Where "Update" goes when the admin has not set a store link.
const defaultStoreUrl = 'https://play.google.com/store/apps/details?id=com.gora.gora_driver';
