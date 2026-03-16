import 'package:supabase/supabase.dart';

import 'key_value_store.dart';

class AuthAsyncStorage extends GotrueAsyncStorage {
  const AuthAsyncStorage(this._store);

  final KeyValueStore _store;

  @override
  Future<String?> getItem({required String key}) {
    return _store.read(key);
  }

  @override
  Future<void> removeItem({required String key}) {
    return _store.delete(key);
  }

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) {
    return _store.write(key, value);
  }
}
