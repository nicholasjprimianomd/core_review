import 'key_value_store.dart';

KeyValueStore createPlatformKeyValueStore({
  required String namespace,
}) {
  throw UnsupportedError(
    'KeyValueStore is not supported on this platform.',
  );
}
