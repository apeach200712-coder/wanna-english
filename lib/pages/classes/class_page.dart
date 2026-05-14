import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/class_model.dart';
import '../../services/class_management_service.dart';
import '../../services/class_service.dart';
import 'class_detail_page.dart';

class ClassPage extends StatefulWidget {
  const ClassPage({super.key});

  @override
  State<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<ClassPage> {
  bool _isLoading = true;
  List<ClassDisplayItem> _classes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final managementService = ClassManagementService(prefs: prefs);
    final service = ClassService(prefs: prefs);
    await managementService.ensureClassMetaForStudentNames();
    await service.initializeFromMockIfNeeded();
    final classes = await service.getDisplayItems();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      _isLoading = false;
    });
  }

  Future<void> _addClass() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClassDetailPage()),
    );
    await _load();
  }

  Future<void> _deleteClass(ClassDisplayItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('반 삭제'),
        content: Text('"${item.displayName}"을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    final service = ClassManagementService(prefs: prefs);
    await service.deleteClass(item.meta);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('클래스 관리')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
          ? const Center(child: Text('등록된 반이 없습니다.'))
          : ListView.builder(
              itemCount: _classes.length,
              itemBuilder: (context, index) {
                final item = _classes[index];
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: item.meta.color),
                    title: Text(item.displayName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Chip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              item.meta.programType.label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            labelPadding: EdgeInsets.zero,
                          ),
                        ),
                        Text(item.meta.scheduleSummary),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClassDetailPage(classId: item.id),
                        ),
                      );
                      await _load();
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteClass(item),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addClass,
        child: const Icon(Icons.add),
      ),
    );
  }
}
