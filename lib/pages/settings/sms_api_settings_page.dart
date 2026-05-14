import 'package:flutter/material.dart';

import '../../widgets/dial_pad_phone_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/sms_service.dart';
import '../../theme/app_colors.dart';

/// HTTP SMS API (학부모 리포트 일괄 전송용). 서버는 POST JSON { to, from, message } 와 Bearer 토큰을 지원해야 합니다.
class SmsApiSettingsPage extends StatefulWidget {
  const SmsApiSettingsPage({super.key});

  @override
  State<SmsApiSettingsPage> createState() => _SmsApiSettingsPageState();
}

class _SmsApiSettingsPageState extends State<SmsApiSettingsPage> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _senderCtrl = TextEditingController();
  bool _loading = true;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = prefs.getString(SMSService.prefKeyApiUrl) ?? '';
      _tokenCtrl.text = prefs.getString(SMSService.prefKeyApiToken) ?? '';
      _senderCtrl.text = prefs.getString(SMSService.prefKeySender) ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SMSService.prefKeyApiUrl, _urlCtrl.text.trim());
    await prefs.setString(SMSService.prefKeyApiToken, _tokenCtrl.text.trim());
    await prefs.setString(SMSService.prefKeySender, _senderCtrl.text.trim());
    if (!mounted) return;
    final ok = await SMSService.isConfigured(prefs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'SMS API 설정을 저장했습니다.'
              : 'URL·토큰·발신번호를 모두 입력해 주세요.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SMS API 설정'),
        backgroundColor: AppColors.overlay,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '학부모 리포트·공지 일괄 전송은 이 앱이 귀하의 SMS 게이트웨이로 HTTP 요청을 보내는 방식입니다. '
                  '데이터는 이 기기(앱)에 저장된 학생·성적·숙제 정보를 바탕으로 학생별로 자동 작성됩니다.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://api.example.com/sms',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _tokenCtrl,
                  decoration: InputDecoration(
                    labelText: 'Bearer 토큰',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                  obscureText: _obscureToken,
                  autocorrect: false,
                ),
                const SizedBox(height: 14),
                DialPadPhoneField(
                  controller: _senderCtrl,
                  sheetTitle: '발신번호',
                  decoration: const InputDecoration(
                    labelText: '발신번호 (SMS_SENDER)',
                    hintText: '등록된 발신 전화번호 또는 발신 ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  child: const Text('저장'),
                ),
                const SizedBox(height: 16),
                Text(
                  '또는 빌드 시: flutter run --dart-define=SMS_API_URL=... '
                  '--dart-define=SMS_API_TOKEN=... --dart-define=SMS_SENDER=...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}
