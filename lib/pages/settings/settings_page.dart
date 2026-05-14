import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../classes/class_page.dart';
import 'academy_info_page.dart';
import 'sms_api_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: AppColors.overlay,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '운영 설정',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.business_rounded,
                color: AppColors.blue,
              ),
              title: const Text('학원 정보'),
              subtitle: const Text('학원명, 지점명, 연락처'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AcademyInfoPage()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.class_rounded, color: AppColors.green),
              title: const Text('클래스 관리'),
              subtitle: const Text('반 목록, 시간/요일 메모'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ClassPage()),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sms_outlined, color: AppColors.purple),
              title: const Text('SMS API'),
              subtitle: const Text('학부모 리포트·공지 일괄 전송용 서버 주소'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SmsApiSettingsPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
