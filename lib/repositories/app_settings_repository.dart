import 'package:flutter/material.dart';

import 'key_value_store.dart';

class AppSettingsRepository {
  static const double defaultTextScale = 1.0;
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.5;

  AppSettingsRepository({KeyValueStore? store})
    : _store = store ?? createKeyValueStore(namespace: 'core_review_settings');

  final KeyValueStore _store;

  Future<ThemeMode> loadThemeMode() async {
    final raw = await _store.read('theme_mode');
    if (raw == null || raw.isEmpty) {
      return ThemeMode.dark;
    }

    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    await _store.write('theme_mode', themeMode.name);
  }

  Future<double> loadTextScale() async {
    final raw = await _store.read('text_scale');
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null) {
      return defaultTextScale;
    }
    return parsed.clamp(minTextScale, maxTextScale);
  }

  Future<void> saveTextScale(double textScale) async {
    final clamped = textScale.clamp(minTextScale, maxTextScale);
    await _store.write('text_scale', clamped.toString());
  }

  static const String _hideExamQuestionNavigatorKey = 'hide_exam_question_navigator';

  Future<bool> loadHideExamQuestionNavigator() async {
    final raw = await _store.read(_hideExamQuestionNavigatorKey);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  Future<void> saveHideExamQuestionNavigator(bool value) async {
    await _store.write(_hideExamQuestionNavigatorKey, value ? '1' : '0');
  }
}
