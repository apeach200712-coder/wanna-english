import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/dial_pad_phone_field.dart';

class AcademyInfoPage extends StatefulWidget {
  const AcademyInfoPage({super.key});

  @override
  State<AcademyInfoPage> createState() => _AcademyInfoPageState();
}

class _AcademyInfoPageState extends State<AcademyInfoPage> {
  static const _academyNameKey = 'academy_info_name_v1';
  static const _branchNameKey = 'academy_info_branch_v1';
  static const _phoneKey = 'academy_info_phone_v1';
  static const _addressKey = 'academy_info_address_v1';

  final _academyCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _academyCtrl.dispose();
    _branchCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _academyCtrl.text = prefs.getString(_academyNameKey) ?? '글로벌에듀';
    _branchCtrl.text = prefs.getString(_branchNameKey) ?? '둔촌오륜';
    _phoneCtrl.text = prefs.getString(_phoneKey) ?? '';
    _addressCtrl.text = prefs.getString(_addressKey) ?? '';
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_academyNameKey, _academyCtrl.text.trim());
    await prefs.setString(_branchNameKey, _branchCtrl.text.trim());
    await prefs.setString(_phoneKey, _phoneCtrl.text.trim());
    await prefs.setString(_addressKey, _addressCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('학원 정보가 저장되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학원 정보')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _field(
                  controller: _academyCtrl,
                  label: '학원명',
                  hint: '예: 글로벌에듀',
                ),
                const SizedBox(height: 12),
                _field(controller: _branchCtrl, label: '지점명', hint: '예: 둔촌오륜'),
                const SizedBox(height: 12),
                DialPadPhoneField(
                  controller: _phoneCtrl,
                  sheetTitle: '대표 연락처',
                  decoration: InputDecoration(
                    labelText: '대표 연락처',
                    hintText: '예: 0212345678',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _addressCtrl,
                  label: '주소',
                  hint: '예: 서울시 강동구 ...',
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _save, child: const Text('저장')),
              ],
            ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
