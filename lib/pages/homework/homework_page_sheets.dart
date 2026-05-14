part of 'homework_page.dart';

// ─── Bottom sheet: manage sections ───────────────────────────────────────────

class _ManageSectionsSheet extends StatefulWidget {
  final List<HomeworkSection> sections;
  final Future<void> Function(String sectionId, String newName) onRename;
  final void Function(String sectionId) onDelete;

  const _ManageSectionsSheet({
    required this.sections,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_ManageSectionsSheet> createState() => _ManageSectionsSheetState();
}

class _ManageSectionsSheetState extends State<_ManageSectionsSheet> {
  late List<HomeworkSection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = List.from(widget.sections);
  }

  Future<void> _showRenameDialog(HomeworkSection section) async {
    final ctrl = TextEditingController(text: section.sectionName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('섹션 이름 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '새 이름 입력'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty && result != section.sectionName) {
      await widget.onRename(section.sectionId, result);
      setState(() {
        _sections = _sections.map((s) {
          if (s.sectionId == section.sectionId) {
            return HomeworkSection(
              sectionId: s.sectionId,
              categoryId: s.categoryId,
              sectionName: result,
              isDefault: s.isDefault,
              subSection: s.subSection,
              detailMemo: s.detailMemo,
              checkCount: s.checkCount,
            );
          }
          return s;
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '섹션 관리',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '이번 주 이 반에 적용된 섹션입니다',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            if (_sections.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('섹션이 없습니다'),
              )
            else
              ..._sections.map(
                (s) => ListTile(
                  dense: true,
                  title: Text(s.sectionName),
                  contentPadding: EdgeInsets.zero,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppColors.primary,
                        onPressed: () => _showRenameDialog(s),
                        tooltip: '이름 수정',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.red[400],
                        onPressed: () {
                          widget.onDelete(s.sectionId);
                        },
                        tooltip: '삭제',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: add section ────────────────────────────────────────────────

class _AddSectionSheet extends StatefulWidget {
  final List<HomeworkSectionTemplate> available;
  final ValueChanged<HomeworkSectionTemplate> onSelected;
  final ValueChanged<String> onCreateNew;

  const _AddSectionSheet({
    required this.available,
    required this.onSelected,
    required this.onCreateNew,
  });

  @override
  State<_AddSectionSheet> createState() => _AddSectionSheetState();
}

class _AddSectionSheetState extends State<_AddSectionSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _showNew = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '섹션 추가',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (widget.available.isEmpty && !_showNew)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('추가 가능한 기본 섹션이 없습니다'),
              )
            else
              ...widget.available.map(
                (t) => ListTile(
                  dense: true,
                  title: Text(t.sectionName),
                  onTap: () => widget.onSelected(t),
                ),
              ),
            const Divider(),
            _showNew
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '새 섹션 이름',
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) widget.onCreateNew(v);
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_ctrl.text.trim().isNotEmpty) {
                            widget.onCreateNew(_ctrl.text);
                          }
                        },
                        child: const Text('추가'),
                      ),
                    ],
                  )
                : ListTile(
                    dense: true,
                    leading: const Icon(Icons.add),
                    title: const Text('새 섹션 직접 입력'),
                    onTap: () => setState(() => _showNew = true),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: sub-section ────────────────────────────────────────────────

class _SubSectionSheet extends StatefulWidget {
  final String sectionName;
  final List<String> options;
  final String? current;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onCustom;
  final VoidCallback onClear;
  final Future<void> Function(String value) onRemove;
  final Future<void> Function(String oldValue, String newValue) onRenameOption;

  const _SubSectionSheet({
    required this.sectionName,
    required this.options,
    required this.current,
    required this.onSelected,
    required this.onCustom,
    required this.onClear,
    required this.onRemove,
    required this.onRenameOption,
  });

  @override
  State<_SubSectionSheet> createState() => _SubSectionSheetState();
}

class _SubSectionSheetState extends State<_SubSectionSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _showCustom = false;
  late List<String> _options;

  @override
  void initState() {
    super.initState();
    _options = List.from(widget.options);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _showRenameDialog(String option) async {
    final ctrl = TextEditingController(text: option);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('하위섹션 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '새 이름 입력'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty && result != option) {
      await widget.onRenameOption(option, result);
      setState(() {
        final idx = _options.indexOf(option);
        if (idx >= 0) _options[idx] = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.sectionName} 하위섹션',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (widget.current != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.close, size: 16, color: Colors.grey),
                title: const Text('선택 해제'),
                onTap: widget.onClear,
              ),
            ..._options.map(
              (o) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(o),
                selected: o == widget.current,
                selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                onTap: () => widget.onSelected(o),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      color: Colors.grey[500],
                      onPressed: () => _showRenameDialog(o),
                      tooltip: '수정',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: Colors.red[300],
                      onPressed: () async {
                        await widget.onRemove(o);
                        setState(() => _options.remove(o));
                      },
                      tooltip: '삭제',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const Divider(),
            _showCustom
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '기타 입력',
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) widget.onCustom(v);
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_ctrl.text.trim().isNotEmpty) {
                            widget.onCustom(_ctrl.text);
                          }
                        },
                        child: const Text('확인'),
                      ),
                    ],
                  )
                : ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.grey,
                    ),
                    title: const Text('기타 입력'),
                    onTap: () => setState(() => _showCustom = true),
                  ),
          ],
        ),
      ),
    );
  }
}
