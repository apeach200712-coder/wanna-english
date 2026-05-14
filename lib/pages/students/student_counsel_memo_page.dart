import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/student_memo_model.dart';
import '../../data/models/student_model.dart';
import '../../services/student_memo_service.dart';
import '../../services/student_service.dart';

class StudentCounselMemoPage extends StatefulWidget {
  final String studentId;

  const StudentCounselMemoPage({super.key, required this.studentId});

  @override
  State<StudentCounselMemoPage> createState() => _StudentCounselMemoPageState();
}

class _StudentCounselMemoPageState extends State<StudentCounselMemoPage> {
  Student? _student;
  List<StudentMemo> _memos = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    final memoService = StudentMemoService(prefs: prefs);
    final student = await studentService.getStudentById(widget.studentId);
    final memos = await memoService.getStudentMemos(widget.studentId);
    if (!mounted) return;
    setState(() {
      _student = student;
      _memos = memos;
      _isLoading = false;
    });
  }

  Future<void> _addMemo() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('상담 메모 추가'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '상담 내용을 입력하세요.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    final content = controller.text.trim();
    if (saved != true || content.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final memoService = StudentMemoService(prefs: prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    await memoService.saveMemo(
      StudentMemo(
        id: const Uuid().v4(),
        studentId: widget.studentId,
        content: content,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _load();
  }

  Future<void> _deleteMemo(StudentMemo memo) async {
    final prefs = await SharedPreferences.getInstance();
    final memoService = StudentMemoService(prefs: prefs);
    await memoService.deleteMemo(memo.id);
    await _load();
  }

  String _formatDate(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 메모'),
        actions: [
          IconButton(onPressed: _addMemo, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_student != null)
                  Text(
                    _student!.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_memos.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('저장된 상담 메모가 없습니다.'),
                    ),
                  )
                else
                  ..._memos.map(
                    (memo) => Card(
                      child: ListTile(
                        title: Text(memo.content),
                        subtitle: Text(_formatDate(memo.updatedAt)),
                        trailing: IconButton(
                          onPressed: () => _deleteMemo(memo),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMemo,
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('메모 추가'),
      ),
    );
  }
}
