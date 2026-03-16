import 'dart:io';

Future<Directory> resolveCoreReviewStorageDirectory({
  Directory? overrideDirectory,
}) async {
  if (overrideDirectory != null) {
    return overrideDirectory;
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}CoreReview');
    }
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    return Directory('$home${Platform.pathSeparator}.core_review');
  }

  return Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}core_review',
  );
}
