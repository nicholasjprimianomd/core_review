import 'key_value_store_stub.dart'
    if (dart.library.io) 'key_value_store_io.dart'
    if (dart.library.js_interop) 'key_value_store_web.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

KeyValueStore createKeyValueStore({
  required String namespace,
}) {
  return createPlatformKeyValueStore(namespace: namespace);
}
