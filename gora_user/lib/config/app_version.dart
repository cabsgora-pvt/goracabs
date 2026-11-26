/// This build's version name — the `version:` in pubspec.yaml without its
/// `+build` number. Bump the two together: test/app_version_test.dart fails
/// when they differ. (The app has no package_info_plus; a constant is enough
/// to compare against the server's minimum / latest version.)
const String kAppVersion = '1.6.0';
