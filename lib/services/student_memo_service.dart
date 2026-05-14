import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/student_memo_model.dart';

class StudentMemoService {
  static const _key = 'student_memo_v1';

  final SharedPreferences _prefs;

  const StudentMemoService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<List<StudentMemo>> getAllMemos() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final memos = decoded
          .whereType<Map<String, dynamic>>()
          .map(StudentMemo.fromJson)
          .toList();
      memos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return memos;
    } catch (_) {
      return const [];
    }
  }

  Future<List<StudentMemo>> getStudentMemos(String studentId) async {
    final all = await getAllMemos();
    return all.where((memo) => memo.studentId == studentId).toList();
  }

  Future<void> saveMemo(StudentMemo memo) async {
    final all = (await getAllMemos()).toList();
    final index = all.indexWhere((item) => item.id == memo.id);
    if (index >= 0) {
      all[index] = memo;
    } else {
      all.add(memo);
    }
    await _prefs.setString(
      _key,
      jsonEncode(all.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> deleteMemo(String memoId) async {
    final all = (await getAllMemos()).toList();
    all.removeWhere((memo) => memo.id == memoId);
    await _prefs.setString(
      _key,
      jsonEncode(all.map((item) => item.toJson()).toList()),
    );
  }
}
