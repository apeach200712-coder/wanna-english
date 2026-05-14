part of 'materials_page.dart';

// ── SIDE PANEL ───────────────────────────────────────────────────

class _SidePanel extends StatelessWidget {
  final List<_Folder> folders;
  final List<_Memo> memos;
  final String? activeMemoId;
  final VoidCallback onAddFolder;
  final ValueChanged<String> onDeleteFolder;
  final ValueChanged<String> onRenameFolder;
  final ValueChanged<String> onAddMemo;
  final ValueChanged<String> onDeleteMemo;
  final ValueChanged<String> onRenameMemo;
  final ValueChanged<String> onSelectMemo;
  final VoidCallback onCollapse;
  final ValueChanged<String> onToggleFolder;

  const _SidePanel({
    required this.folders,
    required this.memos,
    required this.activeMemoId,
    required this.onAddFolder,
    required this.onDeleteFolder,
    required this.onRenameFolder,
    required this.onAddMemo,
    required this.onDeleteMemo,
    required this.onRenameMemo,
    required this.onSelectMemo,
    required this.onCollapse,
    required this.onToggleFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 226,
      decoration: BoxDecoration(
        color: AppColors.overlay,
        border: const Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '교재',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.05,
                          color: AppColors.navy,
                        ),
                      ),
                      Text(
                        '스튜디오',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.05,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: AppColors.subText,
                  ),
                  onPressed: onCollapse,
                  tooltip: '패널 접기',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.create_new_folder_rounded,
                    size: 20,
                    color: AppColors.blue,
                  ),
                  onPressed: onAddFolder,
                  tooltip: '새 폴더',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          // Tree
          Expanded(
            child: folders.isEmpty
                ? const Center(
                    child: Text(
                      '+ 버튼으로\n폴더를 추가하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.subText, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: folders.length,
                    itemBuilder: (ctx, i) {
                      final folder = folders[i];
                      final folderMemos = memos
                          .where((m) => m.folderId == folder.id)
                          .toList();
                      return _FolderTile(
                        folder: folder,
                        memos: folderMemos,
                        activeMemoId: activeMemoId,
                        onToggle: () => onToggleFolder(folder.id),
                        onRename: () => onRenameFolder(folder.id),
                        onDelete: () => onDeleteFolder(folder.id),
                        onAddMemo: () => onAddMemo(folder.id),
                        onDeleteMemo: onDeleteMemo,
                        onRenameMemo: onRenameMemo,
                        onSelectMemo: onSelectMemo,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedStudioPanelTab extends StatelessWidget {
  final VoidCallback onExpand;

  const _CollapsedStudioPanelTab({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.overlay,
        border: const Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Center(
        child: Tooltip(
          message: '교재 스튜디오 펼치기',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExpand,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 30,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.subText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final _Folder folder;
  final List<_Memo> memos;
  final String? activeMemoId;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddMemo;
  final ValueChanged<String> onDeleteMemo;
  final ValueChanged<String> onRenameMemo;
  final ValueChanged<String> onSelectMemo;

  const _FolderTile({
    required this.folder,
    required this.memos,
    required this.activeMemoId,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onAddMemo,
    required this.onDeleteMemo,
    required this.onRenameMemo,
    required this.onSelectMemo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder header
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  folder.isExpanded
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded,
                  color: folder.color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Add memo
                GestureDetector(
                  onTap: onAddMemo,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.add, size: 16, color: AppColors.subText),
                  ),
                ),
                PopupMenuButton<String>(
                  iconSize: 16,
                  icon: const Icon(
                    Icons.more_horiz,
                    color: AppColors.subText,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('삭제', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'rename') onRename();
                    if (val == 'delete') onDelete();
                  },
                ),
              ],
            ),
          ),
        ),
        // Memo list
        if (folder.isExpanded) ...[
          ...memos.map(
            (memo) => _MemoTile(
              memo: memo,
              isActive: memo.id == activeMemoId,
              onTap: () => onSelectMemo(memo.id),
              onRename: () => onRenameMemo(memo.id),
              onDelete: () => onDeleteMemo(memo.id),
            ),
          ),
          // Add memo button
          InkWell(
            onTap: onAddMemo,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(38, 6, 12, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_circle_outline,
                    size: 14,
                    color: AppColors.subText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '메모 추가',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.subText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 1, color: AppColors.line),
      ],
    );
  }
}

class _MemoTile extends StatelessWidget {
  final _Memo memo;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _MemoTile({
    required this.memo,
    required this.isActive,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isActive ? AppColors.blueSoft : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(38, 7, 4, 7),
        child: Row(
          children: [
            Icon(
              Icons.sticky_note_2_rounded,
              size: 14,
              color: isActive ? AppColors.blue : AppColors.subText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                memo.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  color: isActive ? AppColors.blue : AppColors.navy,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${memo.pages.length}p',
              style: const TextStyle(fontSize: 11, color: AppColors.subText),
            ),
            PopupMenuButton<String>(
              iconSize: 14,
              icon: const Icon(
                Icons.more_horiz,
                color: AppColors.subText,
                size: 14,
              ),
              padding: EdgeInsets.zero,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('이름 변경')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('삭제', style: TextStyle(color: Colors.red)),
                ),
              ],
              onSelected: (val) {
                if (val == 'rename') onRename();
                if (val == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── TOP BAR ──────────────────────────────────────────────────────

class _TopStudioSquareBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TopStudioSquareBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.graySoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(icon, size: 17, color: AppColors.subText),
          ),
        ),
      ),
    );
  }
}

class _TopStudioBar extends StatelessWidget {
  final String activeMemoName;
  final int activePage;
  final int pageCount;
  final _PaperStyle paperStyle;
  final bool stylusOnly;
  final bool showStylusToggle;
  final VoidCallback onUploadPdf;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final VoidCallback onAddPage;
  final VoidCallback onRotateCanvas;
  final VoidCallback onAddImage;
  final VoidCallback onOpenPageNavigator;
  final VoidCallback onResetCanvasView;
  final ValueChanged<_PaperStyle> onPaperStyleChange;
  final VoidCallback onToggleStylusOnly;

  const _TopStudioBar({
    required this.activeMemoName,
    required this.activePage,
    required this.pageCount,
    required this.paperStyle,
    required this.stylusOnly,
    required this.showStylusToggle,
    required this.onUploadPdf,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onAddPage,
    required this.onRotateCanvas,
    required this.onAddImage,
    required this.onOpenPageNavigator,
    required this.onResetCanvasView,
    required this.onPaperStyleChange,
    required this.onToggleStylusOnly,
  });

  @override
  Widget build(BuildContext context) {
    final pageLabel = pageCount <= 0 ? '0 / 0' : '${activePage + 1} / $pageCount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        activeMemoName,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_PaperStyle>(
                      tooltip: '노트 스타일',
                      padding: EdgeInsets.zero,
                      color: AppColors.card,
                      onSelected: onPaperStyleChange,
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _PaperStyle.plain,
                          child: Text('무지'),
                        ),
                        PopupMenuItem(
                          value: _PaperStyle.ruled,
                          child: Text('줄노트'),
                        ),
                        PopupMenuItem(
                          value: _PaperStyle.grid,
                          child: Text('격자'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.graySoft,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              paperStyle == _PaperStyle.plain
                                  ? '무지'
                                  : paperStyle == _PaperStyle.ruled
                                  ? '줄노트'
                                  : '격자',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.subText,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppColors.subText,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _MiniIconBtn(
                      icon: Icons.upload_file_rounded,
                      onTap: onUploadPdf,
                      tooltip: 'PDF 업로드',
                    ),
                    if (showStylusToggle) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onToggleStylusOnly,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: stylusOnly
                                ? AppColors.blueSoft
                                : AppColors.graySoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            stylusOnly ? 'Pencil only' : 'Finger + Pencil',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: stylusOnly
                                  ? AppColors.blue
                                  : AppColors.subText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniIconBtn(
                    icon: Icons.chevron_left_rounded,
                    onTap: activePage <= 0 || pageCount <= 0
                        ? null
                        : onPrevPage,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    pageLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _MiniIconBtn(
                    icon: Icons.chevron_right_rounded,
                    onTap: pageCount <= 0 || activePage >= pageCount - 1
                        ? null
                        : onNextPage,
                  ),
                  const SizedBox(width: 4),
                  _MiniIconBtn(
                    icon: Icons.add_rounded,
                    onTap: onAddPage,
                    tooltip: '페이지 추가',
                  ),
                  const SizedBox(width: 4),
                  _TopStudioSquareBtn(
                    icon: Icons.fit_screen_rounded,
                    tooltip: '화면에 맞춤 (줌 초기화)',
                    onTap: onResetCanvasView,
                  ),
                  const SizedBox(width: 4),
                  _TopStudioSquareBtn(
                    icon: Icons.rotate_right_rounded,
                    tooltip: '캔버스 90° 회전',
                    onTap: onRotateCanvas,
                  ),
                  const SizedBox(width: 4),
                  _TopStudioSquareBtn(
                    icon: Icons.add_photo_alternate_outlined,
                    tooltip: '이미지 추가',
                    onTap: onAddImage,
                  ),
                  const SizedBox(width: 4),
                  _TopStudioSquareBtn(
                    icon: Icons.manage_search_rounded,
                    tooltip: '페이지 이동',
                    onTap: onOpenPageNavigator,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PDF STRIP (compact; expand on demand) ───────────────────────

class _PdfStrip extends StatelessWidget {
  final List<_PdfAsset> pdfs;
  final String? activePdfId;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  const _PdfStrip({
    required this.pdfs,
    required this.activePdfId,
    required this.expanded,
    required this.onToggleExpand,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (pdfs.isEmpty) return const SizedBox.shrink();
    final active = pdfs.firstWhere(
      (p) => p.id == activePdfId,
      orElse: () => pdfs.first,
    );
    final label = active.name;

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Material(
          color: AppColors.overlay.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 14,
                    color: AppColors.subText.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.subText.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                  if (pdfs.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${pdfs.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.subText.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.subText.withValues(alpha: 0.85),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: AppColors.overlay.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                child: Row(
                  children: [
                    Text(
                      'PDF (${pdfs.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.subText.withValues(alpha: 0.95),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.expand_less_rounded,
                      size: 18,
                      color: AppColors.subText.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                scrollDirection: Axis.horizontal,
                itemCount: pdfs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final pdf = pdfs[index];
                  final isActive = pdf.id == activePdfId;
                  return GestureDetector(
                    onTap: () => onSelect(pdf.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.blue.withValues(alpha: 0.22)
                            : AppColors.card.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isActive
                              ? AppColors.blue.withValues(alpha: 0.55)
                              : AppColors.line.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 13,
                            color: isActive
                                ? AppColors.blue
                                : AppColors.subText,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              pdf.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? AppColors.blue
                                    : AppColors.subText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => onRemove(pdf.id),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: AppColors.subText.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

