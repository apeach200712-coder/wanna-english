import 'package:flutter/material.dart';

import '../../data/models/exam_score_model.dart';
import '../../theme/app_colors.dart';

/// 유형명 (최대 10자) — 확인 시 trimmed 문자열, 취소 시 null
Future<String?> showNewExamTypeNameDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        '새 유형 추가',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.navy,
        ),
      ),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 10,
        decoration: const InputDecoration(
          labelText: '유형명 입력',
          hintText: '예: 문법시험',
          counterText: '',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(ctx, t.length > 10 ? t.substring(0, 10) : t);
          },
          child: const Text('확인'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}

/// 형식 선택 — 저장 시 선택된 [ExamFormType], 취소 시 null
Future<ExamFormType?> showExamFormatPickerDialog(
  BuildContext context,
  String newTypeName,
) {
  return showDialog<ExamFormType>(
    context: context,
    builder: (ctx) => _FormatPickerDialog(newTypeName: newTypeName),
  );
}

class _FormatPickerDialog extends StatefulWidget {
  final String newTypeName;

  const _FormatPickerDialog({required this.newTypeName});

  @override
  State<_FormatPickerDialog> createState() => _FormatPickerDialogState();
}

class _FormatPickerDialogState extends State<_FormatPickerDialog> {
  ExamFormType _selected = ExamFormType.gradeBased;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text(
        '형식 선택',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: AppColors.navy,
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FormatPreviewCard(
                      title: '등급/백분위형',
                      selected: _selected == ExamFormType.gradeBased,
                      child: _GradeFormMiniPreview(
                        examTitle: widget.newTypeName,
                      ),
                      onTap: () => setState(
                        () => _selected = ExamFormType.gradeBased,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormatPreviewCard(
                      title: '재시험 기준형',
                      selected: _selected == ExamFormType.thresholdBased,
                      child: _ThresholdFormMiniPreview(
                        examTitle: widget.newTypeName,
                      ),
                      onTap: () => setState(
                        () => _selected = ExamFormType.thresholdBased,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class _FormatPreviewCard extends StatelessWidget {
  final String title;
  final bool selected;
  final Widget child;
  final VoidCallback onTap;

  const _FormatPreviewCard({
    required this.title,
    required this.selected,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: selected ? AppColors.primary : AppColors.navy,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _GradeFormMiniPreview extends StatelessWidget {
  final String examTitle;

  const _GradeFormMiniPreview({required this.examTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 8, color: AppColors.subText),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '시험명',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              examTitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            _miniRow('만점', '100점'),
            _miniRow('등급 계산', '5등급제 · 9등급제'),
            _miniRow('입력', '학생별 점수'),
            _miniRow('표시', '등급 · 백분위'),
            _miniRow('분석', '평균·표준편차·최고·최저·미입력'),
          ],
        ),
      ),
    );
  }
}

class _ThresholdFormMiniPreview extends StatelessWidget {
  final String examTitle;

  const _ThresholdFormMiniPreview({required this.examTitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 8, color: AppColors.subText),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '시험명',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              examTitle,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            _miniRow('만점', '50점'),
            _miniRow('재시험 기준', '45점 미만'),
            _miniRow('입력', '학생별 점수'),
            _miniRow('표시', '기준 미만 → 재시험자'),
            _miniRow('분석', '평균·최고·최저·재시험자·미입력'),
          ],
        ),
      ),
    );
  }
}

Widget _miniRow(String a, String b) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(a, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(child: Text(b, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
