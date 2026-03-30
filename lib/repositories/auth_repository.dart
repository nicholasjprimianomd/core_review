import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import '../config/app_config.dart';
import 'auth_async_storage.dart';
import 'key_value_store.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
  });

  final String id;
  final String email;
}

class SignUpResult {
  const SignUpResult({
    required this.user,
    required this.requiresEmailConfirmation,
    required this.message,
  });

  final AuthUser? user;
  final bool requiresEmailConfirmation;
  final String message;
}

class AuthRepository {
  AuthRepository({
    KeyValueStore? store,
    SupabaseClient? client,
  })  : _store = store ?? createKeyValueStore(namespace: 'core_review_auth'),
        _client =
            client ??
            (AppConfig.hasSupabase
                ? SupabaseClient(
                    AppConfig.supabaseUrl,
                    AppConfig.supabaseAnonKey,
                    authOptions: AuthClientOptions(
                      pkceAsyncStorage: AuthAsyncStorage(
                        store ?? createKeyValueStore(namespace: 'core_review_auth'),
                      ),
                    ),
                  )
                : null) {
    _authSubscription = _client?.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
    );
  }

  final KeyValueStore _store;
  final SupabaseClient? _client;

  StreamSubscription<AuthState>? _authSubscription;
  AuthUser? _currentUser;

  bool get isConfigured => _client != null;

  AuthUser? get currentUser => _currentUser;

  SupabaseClient? get client => _client;

  Future<String?> loadAccessToken() async {
    final inMemory = _client?.auth.currentSession?.accessToken;
    if (inMemory != null && inMemory.isNotEmpty) {
      return inMemory;
    }

    final rawSession = await _store.read('session');
    if (rawSession == null || rawSession.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawSession) as Map<String, dynamic>;
      final session = Session.fromJson(decoded);
      final token = session?.accessToken;
      if (token == null || token.isEmpty) {
        return null;
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<AuthUser?> loadSession() async {
    if (_client == null) {
      _currentUser = null;
      return null;
    }

    final rawSession = await _store.read('session');
    if (rawSession != null && rawSession.isNotEmpty) {
      try {
        final response = await _client.auth.recoverSession(rawSession);
        _currentUser = _mapUser(response.user ?? response.session?.user);
        return _currentUser;
      } catch (_) {
        await _store.delete('session');
      }
    }

    _currentUser = _mapUser(_client.auth.currentUser);
    return _currentUser;
  }

  Future<AuthUser?> recoverSessionFromCurrentUrlIfPresent() async {
    if (_client == null) {
      return null;
    }

    final uri = Uri.base;
    final hasCallback = uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error_description') ||
        uri.fragment.contains('access_token') ||
        uri.fragment.contains('error_description');

    if (!hasCallback) {
      return null;
    }

    final response = await _client.auth.getSessionFromUrl(uri);
    _currentUser = _mapUser(response.session.user);
    await _persistSession(response.session);
    return _currentUser;
  }

  Future<AuthUser> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _requireClient().auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = _mapUser(response.user ?? response.session?.user);
    if (user == null) {
      throw StateError('No user returned from sign-in.');
    }
    final session = response.session;
    if (session == null) {
      throw StateError('No session returned from sign-in.');
    }
    _currentUser = user;
    await _persistSession(session);
    return user;
  }

  Future<SignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _requireClient().auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: AppConfig.resolveAuthRedirectUrl(),
    );
    final user = _mapUser(response.user ?? response.session?.user);
    if (user == null) {
      throw StateError('No user returned from sign-up.');
    }
    final session = response.session;
    if (session == null) {
      return SignUpResult(
        user: user,
        requiresEmailConfirmation: true,
        message:
            'Account created. Check your email, confirm the account, then sign in.',
      );
    }
    _currentUser = user;
    await _persistSession(session);
    return SignUpResult(
      user: user,
      requiresEmailConfirmation: false,
      message: 'Account created and signed in.',
    );
  }

  Future<void> signOut() async {
    if (_client == null) {
      _currentUser = null;
      return;
    }

    await _client.auth.signOut();
    _currentUser = null;
    await _store.delete('session');
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase is not configured for this build.');
    }
    return client;
  }

  Future<void> _persistSession(Session session) async {
    await _store.write('session', jsonEncode(session.toJson()));
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    final session = authState.session;
    if (session == null) {
      _currentUser = null;
      await _store.delete('session');
      return;
    }

    _currentUser = _mapUser(session.user);
    await _persistSession(session);
  }

  AuthUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }

    return AuthUser(
      id: user.id,
      email: user.email ?? 'unknown@example.com',
    );
  }
}
