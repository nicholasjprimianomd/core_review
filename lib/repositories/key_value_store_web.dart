import 'package:web/web.dart' as web;

import 'key_value_store.dart';

class WebKeyValueStore implements KeyValueStore {
  WebKeyValueStore({
    required this.namespace,
  });

  final String namespace;

  @override
  Future<String?> read(String key) async {
    return web.window.localStorage.getItem(_namespacedKey(key));
  }

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem(_namespacedKey(key), value);
  }

  @override
  Future<void> delete(String key) async {
    web.window.localStorage.removeItem(_namespacedKey(key));
  }

  String _namespacedKey(String key) => '$namespace::$key';
}

KeyValueStore createPlatformKeyValueStore({
  required String namespace,
}) {
  return WebKeyValueStore(namespace: namespace);
}
