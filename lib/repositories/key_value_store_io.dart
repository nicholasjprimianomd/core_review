import 'dart:io';

import 'key_value_store.dart';
import 'storage_directory.dart';

class IoKeyValueStore implements KeyValueStore {
  IoKeyValueStore({
    required this.namespace,
  });

  final String namespace;

  @override
  Future<String?> read(String key) async {
    final file = await _fileFor(key);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _fileFor(key);
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final file = await _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _fileFor(String key) async {
    final directory = await resolveCoreReviewStorageDirectory();
    final sanitizedKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(
      '${directory.path}${Platform.pathSeparator}$namespace.$sanitizedKey.json',
    );
  }
}

KeyValueStore createPlatformKeyValueStore({
  required String namespace,
}) {
  return IoKeyValueStore(namespace: namespace);
}
