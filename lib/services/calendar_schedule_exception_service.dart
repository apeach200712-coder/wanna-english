import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/calendar_schedule_exception.dart';

class CalendarScheduleExceptionService {
  static const _key = 'calendar_schedule_exceptions_v1';

  final SharedPreferences _prefs;

  CalendarScheduleExceptionService(this._prefs);

  static String dateKeyOf(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Future<List<CalendarScheduleException>> loadAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <CalendarScheduleException>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          final model = CalendarScheduleException.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (!model.isValidForStorage) continue;
          out.add(model);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<CalendarScheduleException> items) async {
    await _prefs.setString(
      _key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addOrReplace(CalendarScheduleException item) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == item.id)
      ..add(item);
    await saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await loadAll()
      ..removeWhere((e) => e.id == id);
    await saveAll(all);
  }

  /// Drop duplicate cancelled markers for the same slot/day.
  Future<void> addCancelledDedup(CalendarScheduleException cancelled) async {
    final all = await loadAll()
      ..removeWhere(
        (e) =>
            e.type == CalendarScheduleExceptionType.cancelled &&
            e.dateKey == cancelled.dateKey &&
            e.sourceScheduleId == cancelled.sourceScheduleId,
      )
      ..add(cancelled);
    await saveAll(all);
  }
}
