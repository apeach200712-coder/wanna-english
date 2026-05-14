import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/student_model.dart';

class SMSService {
  static const String prefKeyApiUrl = 'sms_api_url_v1';
  static const String prefKeyApiToken = 'sms_api_token_v1';
  static const String prefKeySender = 'sms_sender_v1';

  static const String _envUrl = String.fromEnvironment('SMS_API_URL');
  static const String _envToken = String.fromEnvironment('SMS_API_TOKEN');
  static const String _envSender = String.fromEnvironment('SMS_SENDER');

  /// [prefs]가 있으면 디스크 설정을 우선합니다. 없으면 [SharedPreferences.getInstance] 후 환경 변수를 보조로 사용합니다.
  static Future<_SmsRuntimeConfig> _config([SharedPreferences? prefs]) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    var url = p.getString(prefKeyApiUrl)?.trim() ?? '';
    var token = p.getString(prefKeyApiToken)?.trim() ?? '';
    var sender = p.getString(prefKeySender)?.trim() ?? '';
    if (url.isEmpty) url = _envUrl.trim();
    if (token.isEmpty) token = _envToken.trim();
    if (sender.isEmpty) sender = _envSender.trim();
    return _SmsRuntimeConfig(url: url, token: token, sender: sender);
  }

  static Future<bool> isConfigured([SharedPreferences? prefs]) async {
    final c = await _config(prefs);
    return c.isComplete;
  }

  static String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  /// Send SMS via HTTP API.
  static Future<bool> sendSMS({
    required String phoneNumber,
    required String message,
    SharedPreferences? prefs,
  }) async {
    final cfg = await _config(prefs);
    if (!cfg.isComplete) {
      return false;
    }

    final normalizedPhone = _normalizePhone(phoneNumber);
    if (normalizedPhone.isEmpty) {
      return false;
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(cfg.url));
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${cfg.token}',
      );

      final payload = <String, dynamic>{
        'to': normalizedPhone,
        'from': cfg.sender,
        'message': message,
      };
      request.write(jsonEncode(payload));

      final response = await request.close();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Send announcement to selected students via SMS.
  static Future<Map<String, int>> sendAnnouncementToParents({
    required String message,
    required List<Student> students,
    SharedPreferences? prefs,
  }) async {
    if (!await isConfigured(prefs)) {
      return {'success': 0, 'failure': students.length};
    }

    int successCount = 0;
    int failureCount = 0;

    for (final student in students) {
      if (student.parentPhone == null || student.parentPhone!.isEmpty) {
        failureCount++;
        continue;
      }

      if (_normalizePhone(student.parentPhone!).isEmpty) {
        failureCount++;
        continue;
      }

      final success = await sendSMS(
        phoneNumber: student.parentPhone!,
        message: message,
        prefs: prefs,
      );

      if (success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    return {'success': successCount, 'failure': failureCount};
  }

  /// Check if sending is overdue and build notification message.
  static String buildDelayNotification({
    required String className,
    required int delayMinutes,
  }) {
    return '$className 학부모에게 학생 관리 SMS를 전송하시겠습니까?\n\n(예정 시간 대비 $delayMinutes분 지연)';
  }

  static String buildConfigurationErrorMessage() {
    return 'SMS API 설정이 없습니다.\n설정 → SMS API에서 URL·토큰·발신번호를 입력하거나, '
        '빌드 시 SMS_API_URL / SMS_API_TOKEN / SMS_SENDER 를 지정해 주세요.';
  }
}

class _SmsRuntimeConfig {
  final String url;
  final String token;
  final String sender;

  const _SmsRuntimeConfig({
    required this.url,
    required this.token,
    required this.sender,
  });

  bool get isComplete =>
      url.isNotEmpty && token.isNotEmpty && sender.isNotEmpty;
}
