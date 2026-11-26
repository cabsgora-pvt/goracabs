import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why a load failed, in words a rider can act on.
enum LoadFailure { offline, server }

/// Offline when the request never got an answer (no network, DNS failure,
/// timeout); server for everything else (5xx, an error body, bad JSON).
LoadFailure classifyFailure(Object error) {
  if (error is SocketException || error is TimeoutException || error is http.ClientException ||
      error is HandshakeException) {
    return LoadFailure.offline;
  }
  return LoadFailure.server;
}

/// Same, for an ApiService answer map (`{error, httpStatus?}`). The client
/// decodes failures into a map instead of throwing, so "No response from
/// server" / an unreadable page (captive portal) count as offline.
LoadFailure classifyResponse(Map<String, dynamic> res) {
  final status = res['httpStatus'];
  if (status is int && status >= 400) return LoadFailure.server;
  final msg = (res['error'] ?? '').toString().toLowerCase();
  if (msg.contains('check your connection') || msg.contains('no response from server')) {
    return LoadFailure.offline;
  }
  return LoadFailure.server;
}

/// The message to show for [f] when loading [what] ("fares", "packages").
String loadFailureMessage(LoadFailure f, {String what = 'this'}) => switch (f) {
      LoadFailure.offline => "You're offline. Check your internet connection and try again.",
      LoadFailure.server => "Couldn't load $what - our server didn't respond properly. Please try again.",
    };
