import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/models/parent_report_models.dart';

/// 클래스별 인사말·마무리·숙제 하위 체크 상태 (SharedPreferences).
/// 추후 원격 저장소로 옮길 때 이 클래스만 교체하면 됩니다.
class ClassReportSettingsService {
  static const _prefsKey = 'class_report_settings_v1';

  final SharedPreferences _prefs;

  ClassReportSettingsService({required SharedPreferences prefs})
    : _prefs = prefs;

  static String defaultGreetingTemplate() {
    return '안녕하세요, ${AppConstants.academyName} ${AppConstants.academyBranch}입니다.\n'
        '{학생이름} 학생 리포트 안내드립니다.';
  }

  static const String defaultClosingText = '감사합니다.';

  ClassReportSettings defaultsFor(String classKey) {
    return ClassReportSettings(
      classKey: classKey,
      greetingTemplate: defaultGreetingTemplate(),
      closingText: defaultClosingText,
      includeHomeworkCompletion: true,
      includeHomeworkWeakParts: true,
      includeHomeworkResubmissionDeadline: true,
    );
  }

  Future<ClassReportSettings> load(String classKey) async {
    final all = await _readAll();
    final json = all[classKey];
    if (json == null) return defaultsFor(classKey);
    try {
      final parsed = ClassReportSettings.fromJson(
        Map<String, dynamic>.from(json as Map),
      );
      return parsed.copyWith(classKey: classKey);
    } catch (_) {
      return defaultsFor(classKey);
    }
  }

  Future<void> save(ClassReportSettings settings) async {
    final all = await _readAll();
    all[settings.classKey] = settings.toJson();
    await _prefs.setString(_prefsKey, jsonEncode(all));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }
}
