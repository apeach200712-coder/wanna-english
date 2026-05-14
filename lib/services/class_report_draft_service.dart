import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/parent_report_models.dart';

/// 클래스별 리포트 «발송 시점» 옵션·추가안내 (SharedPreferences).
/// [classKey]는 `Student.className` / 공지 화면의 반 이름과 동일한 키를 씁니다.
class ClassReportDraftService {
  static const _prefsKey = 'class_report_send_draft_v1';

  final SharedPreferences _prefs;

  ClassReportDraftService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<ClassReportDraft> load(String classKey) async {
    final all = await _readAll();
    final json = all[classKey];
    if (json == null) return ClassReportDraft.empty();
    try {
      return ClassReportDraft.fromJson(Map<String, dynamic>.from(json as Map));
    } catch (_) {
      return ClassReportDraft.empty();
    }
  }

  Future<void> save(String classKey, ClassReportDraft draft) async {
    final all = await _readAll();
    all[classKey] = draft.toJson();
    await _prefs.setString(_prefsKey, jsonEncode(all));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {};
  }
}

@immutable
class ClassReportDraft {
  final bool includeTodayLesson;
  final bool includeNextHomework;
  final List<String> selectedExamSessionIds;
  final String extraNotice;

  const ClassReportDraft({
    required this.includeTodayLesson,
    required this.includeNextHomework,
    required this.selectedExamSessionIds,
    required this.extraNotice,
  });

  factory ClassReportDraft.empty() => const ClassReportDraft(
        includeTodayLesson: true,
        includeNextHomework: true,
        selectedExamSessionIds: [],
        extraNotice: '',
      );

  ReportSendOptions toSendOptions() {
    return ReportSendOptions(
      includeTodayLesson: includeTodayLesson,
      includeNextHomework: includeNextHomework,
      selectedExamSessionIds: Set<String>.from(selectedExamSessionIds),
    );
  }

  Map<String, dynamic> toJson() => {
        'includeTodayLesson': includeTodayLesson,
        'includeNextHomework': includeNextHomework,
        'selectedExamSessionIds': selectedExamSessionIds,
        'extraNotice': extraNotice,
      };

  factory ClassReportDraft.fromJson(Map<String, dynamic> json) {
    final ids = json['selectedExamSessionIds'];
    return ClassReportDraft(
      includeTodayLesson: json['includeTodayLesson'] as bool? ?? true,
      includeNextHomework: json['includeNextHomework'] as bool? ?? true,
      selectedExamSessionIds: ids is List
          ? ids.map((e) => e.toString()).toList()
          : const [],
      extraNotice: json['extraNotice'] as String? ?? '',
    );
  }
}
