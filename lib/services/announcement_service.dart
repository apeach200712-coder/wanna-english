import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/announcement_model.dart';
import 'class_service.dart';

class AnnouncementService {
  static const String _announcementsKey = 'announcements_v1';
  static const String _smsLogsKey = 'sms_logs_v1';
  static const String _sendingScheduleKey = 'sending_schedule_v1';

  final SharedPreferences _prefs;

  const AnnouncementService({required SharedPreferences prefs})
    : _prefs = prefs;

  /// Save or update an announcement.
  Future<void> saveAnnouncement(Announcement announcement) async {
    await _ensureClassIdMigration();
    final announcements = await getAllAnnouncements();
    final index = announcements.indexWhere((a) => a.id == announcement.id);

    if (index >= 0) {
      announcements[index] = announcement;
    } else {
      announcements.add(announcement);
    }

    final json = jsonEncode(announcements.map((a) => a.toJson()).toList());
    await _prefs.setString(_announcementsKey, json);
  }

  /// Get all announcements.
  Future<List<Announcement>> getAllAnnouncements() async {
    await _ensureClassIdMigration();
    final json = _prefs.getString(_announcementsKey);
    if (json == null) return const [];

    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Announcement.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Get announcements by class.
  Future<List<Announcement>> getAnnouncementsByClass(String className) async {
    final all = await getAllAnnouncements();
    return all.where((a) => a.className == className).toList();
  }

  Future<List<Announcement>> getAnnouncementsByClassId(String classId) async {
    final all = await getAllAnnouncements();
    return all.where((a) => a.classId == classId).toList();
  }

  /// Save SMS log.
  Future<void> saveSMSLog(SMSLog log) async {
    final logs = await getAllSMSLogs();
    logs.add(log);

    final json = jsonEncode(logs.map((l) => l.toJson()).toList());
    await _prefs.setString(_smsLogsKey, json);
  }

  /// Get all SMS logs.
  Future<List<SMSLog>> getAllSMSLogs() async {
    final json = _prefs.getString(_smsLogsKey);
    if (json == null) return const [];

    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SMSLog.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Get SMS logs for an announcement.
  Future<List<SMSLog>> getSMSLogsForAnnouncement(String announcementId) async {
    final all = await getAllSMSLogs();
    return all.where((l) => l.announcementId == announcementId).toList();
  }

  /// Record typical sending time for a class.
  Future<void> recordSendingTime(String className, DateTime time) async {
    final jsonStr = _prefs.getString(_sendingScheduleKey) ?? '{}';
    final schedule = jsonDecode(jsonStr) as Map<String, dynamic>;

    final timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    schedule[className] = timeStr;

    await _prefs.setString(_sendingScheduleKey, jsonEncode(schedule));
  }

  /// Get typical sending time for a class.
  Future<String?> getTypicalSendingTime(String className) async {
    final jsonStr = _prefs.getString(_sendingScheduleKey) ?? '{}';
    final schedule = jsonDecode(jsonStr) as Map<String, dynamic>;
    return schedule[className] as String?;
  }

  /// Check if sending is delayed (> 10 minutes from typical time).
  Future<bool> isDelayedSending(String className) async {
    final typical = await getTypicalSendingTime(className);
    if (typical == null) return false; // No typical time recorded yet

    final parts = typical.split(':');
    if (parts.length != 2) return false;

    final typicalHour = int.tryParse(parts[0]) ?? 0;
    final typicalMinute = int.tryParse(parts[1]) ?? 0;
    final typicalDateTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      typicalHour,
      typicalMinute,
    );

    final now = DateTime.now();
    final difference = now.difference(typicalDateTime).inMinutes;

    return difference > 10;
  }

  /// Delete an announcement.
  Future<void> deleteAnnouncement(String announcementId) async {
    final announcements = await getAllAnnouncements();
    announcements.removeWhere((a) => a.id == announcementId);
    final json = jsonEncode(announcements.map((a) => a.toJson()).toList());
    await _prefs.setString(_announcementsKey, json);
  }

  Future<void> _ensureClassIdMigration() async {
    final classService = ClassService(prefs: _prefs);
    final classMap = {
      for (final item in await classService.getAllClasses())
        item.name.trim(): item.id,
    };

    final raw = _prefs.getString(_announcementsKey);
    if (raw == null) return;

    try {
      final decoded = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      var changed = false;
      for (final item in decoded) {
        final existingId = (item['classId'] as String?)?.trim();
        if (existingId != null && existingId.isNotEmpty) continue;
        final className = (item['className'] as String?)?.trim();
        if (className == null || className.isEmpty) continue;
        final mappedId = classMap[className];
        if (mappedId == null || mappedId.isEmpty) continue;
        item['classId'] = mappedId;
        changed = true;
      }
      if (changed) {
        await _prefs.setString(_announcementsKey, jsonEncode(decoded));
      }
    } catch (_) {
      return;
    }
  }
}
