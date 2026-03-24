import 'package:flutter/foundation.dart';

class AppConfig {
  // Keep the public web client config available when deploy env vars are absent.
  static const String _defaultSupabaseUrl =
      'https://szerwpvldtnamhfpqmih.supabase.co';
  static const String _defaultSupabaseAnonKey =
      'sb_publishable_gmJyumfHSnoOTqpMkVS-qw_A6axiU62';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );
  static const String authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
  );
  static const String assistantApiBaseUrl = String.fromEnvironment(
    'ASSISTANT_API_BASE_URL',
  );
  static const String contentBaseUrl = String.fromEnvironment(
    'CONTENT_BASE_URL',
  );

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // On web the image base is always the page origin (resolved at runtime), so
  // remote content is always available on web regardless of compile-time config.
  static bool get hasRemoteContent => kIsWeb || contentBaseUrl.isNotEmpty;

  static String resolveAuthRedirectUrl() {
    if (authRedirectUrl.isNotEmpty) {
      return authRedirectUrl;
    }

    if (kIsWeb) {
      return Uri.base.origin;
    }

    return 'https://core-review-smoky.vercel.app';
  }

  static String resolveAssistantApiUrl() {
    if (assistantApiBaseUrl.isNotEmpty) {
      final sanitizedBase = assistantApiBaseUrl.endsWith('/')
          ? assistantApiBaseUrl.substring(0, assistantApiBaseUrl.length - 1)
          : assistantApiBaseUrl;
      return '$sanitizedBase/api/assistant';
    }

    if (kIsWeb) {
      return '${Uri.base.origin}/api/assistant';
    }

    return 'https://core-review-smoky.vercel.app/api/assistant';
  }

  /// Keyword search over locally indexed Crack the Core / War Machine PDFs (`api/reference_books_index.json`).
  static String resolveReferenceBooksSearchUrl() {
    if (assistantApiBaseUrl.isNotEmpty) {
      final sanitizedBase = assistantApiBaseUrl.endsWith('/')
          ? assistantApiBaseUrl.substring(0, assistantApiBaseUrl.length - 1)
          : assistantApiBaseUrl;
      return '$sanitizedBase/api/reference-books-search';
    }

    if (kIsWeb) {
      return '${Uri.base.origin}/api/reference-books-search';
    }

    return 'https://core-review-smoky.vercel.app/api/reference-books-search';
  }

  static String? resolveRemoteContentUrl(String relativePath) {
    final String base;
    if (kIsWeb) {
      // Always use the page origin at runtime so image URLs are always correct
      // regardless of what was compiled into the binary.  This is deployment-safe:
      // the same binary works on any domain or preview URL without rebuilding.
      base = Uri.base.origin;
    } else if (contentBaseUrl.isNotEmpty) {
      base = contentBaseUrl.endsWith('/')
          ? contentBaseUrl.substring(0, contentBaseUrl.length - 1)
          : contentBaseUrl;
    } else {
      return null;
    }

    final sanitizedPath = relativePath.startsWith('assets/')
        ? relativePath.substring('assets/'.length)
        : relativePath;
    return '$base/$sanitizedPath';
  }
}
