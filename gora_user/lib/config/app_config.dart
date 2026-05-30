/// Single place to switch between local & production
/// Change ONLY this file when deploying
class AppConfig {
  // ── Production ──
  static const String serverBaseUrl = 'https://goracabs.com';

  // ── Local dev (uncomment to use) ──
  // static const String serverBaseUrl = 'http://localhost:3000';

  static String get apiBaseUrl => '$serverBaseUrl/api';

  /// Build a full image URL from a relative `/uploads/...` path
  static String imageUrl(String relativePath) {
    if (relativePath.isEmpty) return '';
    if (relativePath.startsWith('http')) return relativePath;
    return '$serverBaseUrl$relativePath';
  }
}
