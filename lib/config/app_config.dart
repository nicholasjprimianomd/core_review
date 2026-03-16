import 'package:flutter/foundation.dart';

class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
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

  static bool get hasRemoteContent => contentBaseUrl.isNotEmpty;

  static String resolveAuthRedirectUrl() {
    if (authRedirectUrl.isNotEmpty) {
      return authRedirectUrl;
    }

    if (kIsWeb) {
      return Uri.base.origin;
    }

    return 'https://project-570gl.vercel.app';
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

    return 'https://project-570gl.vercel.app/api/assistant';
  }

  static String? resolveRemoteContentUrl(String relativePath) {
    if (!hasRemoteContent) {
      return null;
    }

    final sanitizedBase = contentBaseUrl.endsWith('/')
        ? contentBaseUrl.substring(0, contentBaseUrl.length - 1)
        : contentBaseUrl;
    final sanitizedPath = relativePath.startsWith('assets/')
        ? relativePath.substring('assets/'.length)
        : relativePath;
    return '$sanitizedBase/$sanitizedPath';
  }
}
