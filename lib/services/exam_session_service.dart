import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/exam_score_model.dart';

class ExamSessionService {
  static const String _sessionsKey = 'exam_sessions_v1';

  final SharedPreferences _prefs;

  ExamSessionService({required SharedPreferences prefs}) : _prefs = prefs;

  List<ExamSession> getAllSessions() {
    final raw = _prefs.getString(_sessionsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <ExamSession>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final session = ExamSession.fromJson(Map<String, dynamic>.from(item));
          if (session.id.isEmpty || session.className.isEmpty) continue;
          out.add(session);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<ExamSession> getClassSessions(String className) {
    final all = getAllSessions();
    final filtered = all.where((s) => s.className == className).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  List<ExamSession> getSessions({
    String? className,
    ExamCategory? category,
    DateTime? examDate,
  }) {
    final all = getAllSessions();
    final filtered = all.where((s) {
      if (className != null && s.className != className) return false;
      if (category != null && s.legacyCategory != category) return false;
      if (examDate != null && !_isSameDay(s.examDate, examDate)) return false;
      return true;
    }).toList();

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  ExamSession? getLatestClassSession(String className) {
    final list = getClassSessions(className);
    if (list.isEmpty) return null;
    return list.first;
  }

  Future<void> saveSession(ExamSession session) async {
    final all = List<ExamSession>.from(getAllSessions());
    final idx = all.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      all[idx] = session;
    } else {
      all.add(session);
    }
    await _prefs.setString(
      _sessionsKey,
      jsonEncode(all.map((e) => e.toJson()).toList()),
    );
  }

  int countSessionsForExamType(String className, String examTypeId) {
    return getAllSessions()
        .where((s) => s.className == className && s.examTypeId == examTypeId)
        .length;
  }

  Future<void> deleteSession(String sessionId) async {
    final all = List<ExamSession>.from(getAllSessions());
    all.removeWhere((s) => s.id == sessionId);
    await _prefs.setString(
      _sessionsKey,
      jsonEncode(all.map((e) => e.toJson()).toList()),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
