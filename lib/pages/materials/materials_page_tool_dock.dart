part of 'materials_page.dart';

SliderThemeData _materialsToolbarSliderTheme(
  BuildContext context, {
  required double thumbRadius,
}) {
  return SliderTheme.of(context).copyWith(
    trackHeight: 3,
    thumbColor: AppColors.navy,
    overlayColor: AppColors.navy.withValues(alpha: 0.14),
    activeTrackColor: AppColors.gray,
    inactiveTrackColor: AppColors.line,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
    overlayShape: RoundSliderOverlayShape(overlayRadius: thumbRadius + 4),
  );
}

// ── Text tool toolbar (GoodNotes-style, in main dock row) ───────

class _TextDockBindings {
  final String fontShortLabel;
  final int fontSizeRound;
  final bool bold;
  final bool italic;
  final bool underline;
  final int alignIndex;
  final bool hasBackground;
  final bool hasBorder;
  final _TextStyleColorTarget colorTarget;
  final VoidCallback onFontMenu;
  final VoidCallback onDecFontSize;
  final VoidCallback onIncFontSize;
  final void Function(BuildContext anchorContext)? onFontSizeNumberTap;
  final VoidCallback onPickColor;
  final ValueChanged<_TextStyleColorTarget> onColorTarget;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onAlignLeft;
  final VoidCallback onAlignCenter;
  final VoidCallback onAlignRight;
  final VoidCallback onToggleBg;
  final VoidCallback onToggleBorder;

  const _TextDockBindings({
    required this.fontShortLabel,
    required this.fontSizeRound,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.alignIndex,
    required this.hasBackground,
    required this.hasBorder,
    required this.colorTarget,
    required this.onFontMenu,
    required this.onDecFontSize,
    required this.onIncFontSize,
    this.onFontSizeNumberTap,
    required this.onPickColor,
    required this.onColorTarget,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onAlignLeft,
    required this.onAlignCenter,
    required this.onAlignRight,
    required this.onToggleBg,
    required this.onToggleBorder,
  });
}

/// Thin row below the main tool dock (text formatting only).
class _TextAuxiliarySettingsBar extends StatelessWidget {
  final double width;
  final bool attachedBelowMainDock;
  final _TextDockBindings bindings;
  final VoidCallback onClose;

  const _TextAuxiliarySettingsBar({
    required this.width,
    this.attachedBelowMainDock = false,
    required this.bindings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: AppColors.card,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      border: attachedBelowMainDock
          ? const Border(
              left: BorderSide(color: AppColors.line),
              right: BorderSide(color: AppColors.line),
              bottom: BorderSide(color: AppColors.line),
            )
          : Border.all(color: AppColors.line),
    );
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        width: width,
        decoration: deco,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _TextDockFormattingBar(b: bindings, compact: true),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.subText),
                tooltip: '닫기',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextDockFormattingBar extends StatelessWidget {
  final _TextDockBindings b;
  final bool compact;

  const _TextDockFormattingBar({
    required this.b,
    this.compact = false,
  });

  double get _hit => compact ? 32 : 44;

  double get _ico => compact ? 17 : 22;

  Widget _chip({
    required String tooltip,
    required Widget child,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.blue.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: _hit,
            height: _hit,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _colorTargetChip({
    required bool compact,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: selected ? AppColors.blue.withValues(alpha: 0.14) : AppColors.graySoft,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.blue : AppColors.subText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactFontSizeStepper(_TextDockBindings b) {
    return Material(
      color: AppColors.graySoft,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: b.onDecFontSize,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            child: SizedBox(
              width: _hit - 4,
              height: _hit,
              child: Icon(Icons.remove_rounded, size: _ico - 2, color: AppColors.navy),
            ),
          ),
          Builder(
            builder: (ctx) {
              final mid = Text(
                '${b.fontSizeRound}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              );
              final tap = b.onFontSizeNumberTap;
              return ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: tap == null
                    ? Center(child: mid)
                    : InkWell(
                        onTap: () => tap(ctx),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Center(child: mid),
                        ),
                      ),
              );
            },
          ),
          InkWell(
            onTap: b.onIncFontSize,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
            child: SizedBox(
              width: _hit - 4,
              height: _hit,
              child: Icon(Icons.add_rounded, size: _ico - 2, color: AppColors.navy),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '글꼴',
          child: Material(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: b.onFontMenu,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 5 : 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.fontShortLabel,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.navy,
                      size: compact ? 18 : 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _compactFontSizeStepper(b),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            '색상 적용',
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700,
              color: AppColors.subText,
            ),
          ),
        ),
        _colorTargetChip(
          compact: compact,
          label: '글자',
          selected: b.colorTarget == _TextStyleColorTarget.text,
          onTap: () => b.onColorTarget(_TextStyleColorTarget.text),
        ),
        _colorTargetChip(
          compact: compact,
          label: '채움',
          selected: b.colorTarget == _TextStyleColorTarget.fill,
          onTap: () => b.onColorTarget(_TextStyleColorTarget.fill),
        ),
        _colorTargetChip(
          compact: compact,
          label: '테두리',
          selected: b.colorTarget == _TextStyleColorTarget.border,
          onTap: () => b.onColorTarget(_TextStyleColorTarget.border),
        ),
        const SizedBox(width: 10),
        _chip(
          tooltip: '색상 팔레트',
          onTap: b.onPickColor,
          child: Icon(Icons.palette_outlined, color: AppColors.navy, size: _ico),
        ),
        const SizedBox(width: 6),
        _chip(
          tooltip: '굵게',
          active: b.bold,
          onTap: b.onBold,
          child: Icon(
            Icons.format_bold_rounded,
            color: b.bold ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        _chip(
          tooltip: '기울임',
          active: b.italic,
          onTap: b.onItalic,
          child: Icon(
            Icons.format_italic_rounded,
            color: b.italic ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        _chip(
          tooltip: '밑줄',
          active: b.underline,
          onTap: b.onUnderline,
          child: Icon(
            Icons.format_underlined_rounded,
            color: b.underline ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        const SizedBox(width: 10),
        _chip(
          tooltip: '왼쪽 정렬',
          active: b.alignIndex == 0,
          onTap: b.onAlignLeft,
          child: Icon(
            Icons.format_align_left_rounded,
            color: b.alignIndex == 0 ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        _chip(
          tooltip: '가운데 정렬',
          active: b.alignIndex == 1,
          onTap: b.onAlignCenter,
          child: Icon(
            Icons.format_align_center_rounded,
            color: b.alignIndex == 1 ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        _chip(
          tooltip: '오른쪽 정렬',
          active: b.alignIndex == 2,
          onTap: b.onAlignRight,
          child: Icon(
            Icons.format_align_right_rounded,
            color: b.alignIndex == 2 ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        const SizedBox(width: 8),
        _chip(
          tooltip: b.hasBackground ? '배경 없음' : '배경색',
          active: b.hasBackground,
          onTap: b.onToggleBg,
          child: Icon(
            Icons.format_color_fill_rounded,
            color: b.hasBackground ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
        _chip(
          tooltip: b.hasBorder ? '테두리 끄기' : '테두리',
          active: b.hasBorder,
          onTap: b.onToggleBorder,
          child: Icon(
            Icons.crop_square_rounded,
            color: b.hasBorder ? AppColors.blue : AppColors.navy,
            size: _ico,
          ),
        ),
      ],
    );
  }
}

// ── TOOL DOCK ────────────────────────────────────────────────────

class _ToolDock extends StatelessWidget {
  final _ToolType tool;
  final _ToolDockPanelKind? dockPanel;
  final int lassoTextSelectionCount;
  final List<Color> recentColors;
  final double width;
  final Color color;
  final double opacity;
  final _EraserMode eraserMode;
  final int laserModeIndex;
  final int laserDismissMs;
  final ValueChanged<int> onLaserDismissMsChanged;
  final String? textColorTargetLabel;
  final bool attachTextFormatRowBelow;
  final ValueChanged<_ToolType> onToolChange;
  final VoidCallback onToggleEraserMode;
  final ValueChanged<double> onWidthChange;
  final ValueChanged<double> onWidthChangeEnd;
  final ValueChanged<double> onOpacityChange;
  final ValueChanged<double> onOpacityChangeEnd;
  final ValueChanged<Color> onColorChange;
  final VoidCallback onColorCircleTap;
  final VoidCallback onAdvancedColorFromPanel;
  final double? textFillAlphaForPanel;
  final ValueChanged<double>? onTextFillAlphaChanged;
  final VoidCallback? onTextFillAlphaDragStart;
  final VoidCallback? onTextFillAlphaChangeEnd;
  final void Function(BuildContext panelContext)? onTextFillAlphaValueTap;
  final VoidCallback onWidthChipTap;
  final void Function(BuildContext panelContext) onWidthValueTap;
  final void Function(BuildContext panelContext) onOpacityValueTap;
  final bool undoEnabled;
  final bool redoEnabled;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onDeleteCurrentPage;
  final VoidCallback onCloseDockPanel;

  const _ToolDock({
    required this.tool,
    required this.dockPanel,
    this.lassoTextSelectionCount = 0,
    required this.recentColors,
    required this.width,
    required this.color,
    required this.opacity,
    required this.eraserMode,
    required this.laserModeIndex,
    required this.laserDismissMs,
    required this.onLaserDismissMsChanged,
    this.textColorTargetLabel,
    this.attachTextFormatRowBelow = false,
    required this.onToolChange,
    required this.onToggleEraserMode,
    required this.onWidthChange,
    required this.onWidthChangeEnd,
    required this.onOpacityChange,
    required this.onOpacityChangeEnd,
    required this.onColorChange,
    required this.onColorCircleTap,
    required this.onAdvancedColorFromPanel,
    this.textFillAlphaForPanel,
    this.onTextFillAlphaChanged,
    this.onTextFillAlphaDragStart,
    this.onTextFillAlphaChangeEnd,
    this.onTextFillAlphaValueTap,
    required this.onWidthChipTap,
    required this.onWidthValueTap,
    required this.onOpacityValueTap,
    required this.undoEnabled,
    required this.redoEnabled,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onDeleteCurrentPage,
    required this.onCloseDockPanel,
  });

  @override
  Widget build(BuildContext context) {
    final isEraserTool = tool == _ToolType.eraser;
    final colorButtonEnabled =
        !isEraserTool &&
        tool != _ToolType.text &&
        (tool == _ToolType.pen ||
            tool == _ToolType.pencil ||
            tool == _ToolType.highlighter ||
            tool == _ToolType.laser ||
            (tool == _ToolType.lasso && lassoTextSelectionCount > 0));
    final showWidthChip =
        tool != _ToolType.text &&
        (tool == _ToolType.pen ||
            tool == _ToolType.pencil ||
            tool == _ToolType.highlighter ||
            tool == _ToolType.laser ||
            (isEraserTool && eraserMode == _EraserMode.pixel));

    final widthLabel = switch (tool) {
      _ToolType.lasso || _ToolType.hand => '--',
      _ToolType.text => '${width.round()}',
      _ToolType.eraser =>
        eraserMode == _EraserMode.pixel ? width.toStringAsFixed(1) : '—',
      _ => width.toStringAsFixed(1),
    };

    final widthChipTitle = switch (tool) {
      _ToolType.text => '크기',
      _ToolType.eraser => '크기',
      _ => '두께',
    };

    final settingsPanel = switch (dockPanel) {
      _ToolDockPanelKind.color => _ColorOnlyDockPanel(
        tool: tool,
        color: color,
        recentColors: recentColors,
        colors: _defaultColorPalette,
        textColorTargetLabel: textColorTargetLabel,
        textFillAlpha: textFillAlphaForPanel,
        onTextFillAlphaChanged: onTextFillAlphaChanged,
        onTextFillAlphaDragStart: onTextFillAlphaDragStart,
        onTextFillAlphaChangeEnd: onTextFillAlphaChangeEnd,
        onTextFillAlphaValueTap: onTextFillAlphaValueTap,
        onColorChange: onColorChange,
        onAdvancedColorTap: onAdvancedColorFromPanel,
        onClose: onCloseDockPanel,
      ),
      _ToolDockPanelKind.width => _WidthOnlyDockPanel(
        tool: tool,
        width: width,
        opacity: opacity,
        laserDismissMs: laserDismissMs,
        onLaserDismissMsChanged: onLaserDismissMsChanged,
        onWidthChange: onWidthChange,
        onWidthChangeEnd: onWidthChangeEnd,
        onOpacityChange: onOpacityChange,
        onOpacityChangeEnd: onOpacityChangeEnd,
        onWidthValueTap: onWidthValueTap,
        onOpacityValueTap: onOpacityValueTap,
        onClose: onCloseDockPanel,
      ),
      null => null,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 58,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: attachTextFormatRowBelow
                      ? const BorderRadius.vertical(top: Radius.circular(18))
                      : BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                  boxShadow: softShadow(),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _AaToolButton(
                        active: tool == _ToolType.text,
                        onTap: () => onToolChange(_ToolType.text),
                      ),
                      _CompactToolButton(
                        icon: Icons.edit_rounded,
                        label: _ToolType.pen.label,
                        active: tool == _ToolType.pen,
                        onTap: () => onToolChange(_ToolType.pen),
                      ),
                      _CompactToolButton(
                        icon: Icons.create_rounded,
                        label: _ToolType.pencil.label,
                        active: tool == _ToolType.pencil,
                        onTap: () => onToolChange(_ToolType.pencil),
                      ),
                      _CompactToolButton(
                        icon: Icons.brush_rounded,
                        label: _ToolType.highlighter.label,
                        active: tool == _ToolType.highlighter,
                        onTap: () => onToolChange(_ToolType.highlighter),
                      ),
                      _CompactToolButton(
                        icon: Icons.auto_fix_off_rounded,
                        label: _ToolType.eraser.label,
                        active: tool == _ToolType.eraser,
                        onTap: () => onToolChange(_ToolType.eraser),
                      ),
                      _CompactToolButton(
                        icon: Icons.crop_free_rounded,
                        label: _ToolType.lasso.label,
                        active: tool == _ToolType.lasso,
                        onTap: () => onToolChange(_ToolType.lasso),
                      ),
                      _CompactToolButton(
                        icon: tool == _ToolType.laser && laserModeIndex == 0
                            ? Icons.fiber_manual_record_rounded
                            : Icons.blur_on_rounded,
                        label: _ToolType.laser.label,
                        active: tool == _ToolType.laser,
                        tooltip: tool == _ToolType.laser
                            ? (laserModeIndex == 0
                                  ? '레이저(점) — 다시 누르면 흔적 모드'
                                  : '레이저(흔적) — 다시 누르면 점 모드')
                            : '레이저 포인터',
                        onTap: () => onToolChange(_ToolType.laser),
                      ),
                      const SizedBox(width: 6),
                      _ActionBtn(
                        icon: Icons.undo_rounded,
                        onTap: onUndo,
                        enabled: undoEnabled,
                        compact: true,
                      ),
                      const SizedBox(width: 6),
                      _ActionBtn(
                        icon: Icons.redo_rounded,
                        onTap: onRedo,
                        enabled: redoEnabled,
                        compact: true,
                      ),
                      const SizedBox(width: 10),
                      if (colorButtonEnabled) ...[
                        _ToolbarColorButton(
                          color: color,
                          enabled: true,
                          onTap: onColorCircleTap,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (isEraserTool) ...[
                        _ToolbarModeChip(
                          label: eraserMode == _EraserMode.pixel
                              ? '픽셀'
                              : '획',
                          onTap: onToggleEraserMode,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (showWidthChip) ...[
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onWidthChipTap,
                            borderRadius: BorderRadius.circular(12),
                            child: _ToolbarValueChip(
                              label: widthChipTitle,
                              value: widthLabel,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _ActionBtn(
                        icon: Icons.layers_clear_rounded,
                        onTap: onClear,
                        compact: true,
                      ),
                      const SizedBox(width: 6),
                      _PageDeleteActionBtn(onTap: onDeleteCurrentPage),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
              child: settingsPanel == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(dockPanel),
                      padding: const EdgeInsets.only(top: 6),
                      child: settingsPanel,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Toolbar control: delete entire current canvas page (not stroke clear).
/// Same delete_sweep_rounded glyph as clear (filled bin + lid).
class _PageDeleteActionBtn extends StatelessWidget {
  final VoidCallback onTap;

  const _PageDeleteActionBtn({required this.onTap});

  static const double _box = 32;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '현재 페이지 삭제',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: _box,
          height: _box,
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Center(
            child: Icon(
              Icons.delete_outline_rounded,
              size: _iconSize,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorOnlyDockPanel extends StatelessWidget {
  final _ToolType tool;
  final Color color;
  final List<Color> recentColors;
  final List<Color> colors;
  final ValueChanged<Color> onColorChange;
  final VoidCallback onAdvancedColorTap;
  final VoidCallback onClose;
  final String? textColorTargetLabel;
  final double? textFillAlpha;
  final ValueChanged<double>? onTextFillAlphaChanged;
  final VoidCallback? onTextFillAlphaDragStart;
  final VoidCallback? onTextFillAlphaChangeEnd;
  final void Function(BuildContext panelContext)? onTextFillAlphaValueTap;

  const _ColorOnlyDockPanel({
    required this.tool,
    required this.color,
    required this.recentColors,
    required this.colors,
    required this.onColorChange,
    required this.onAdvancedColorTap,
    required this.onClose,
    this.textColorTargetLabel,
    this.textFillAlpha,
    this.onTextFillAlphaChanged,
    this.onTextFillAlphaDragStart,
    this.onTextFillAlphaChangeEnd,
    this.onTextFillAlphaValueTap,
  });

  @override
  Widget build(BuildContext context) {
    const title = '색상';
    final subtitle = tool == _ToolType.text && textColorTargetLabel != null
        ? '적용: $textColorTargetLabel'
        : switch (tool) {
            _ToolType.highlighter => '형광 색상 (투명도는 두께 패널)',
            _ToolType.pen => '펜 색상',
            _ToolType.pencil => '연필 색상',
            _ToolType.laser => '레이저 색상',
            _ToolType.lasso => '선택한 텍스트',
            _ToolType.text => '텍스트 색상',
            _ToolType.hand => '',
            _ToolType.eraser => '',
          };
    final showFillOpacity =
        tool == _ToolType.text &&
        textFillAlpha != null &&
        onTextFillAlphaChanged != null;
    final alpha = (textFillAlpha ?? 1.0).clamp(0.0, 1.0);
    final transparencyPct = ((1.0 - alpha) * 100).round().clamp(0, 100);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: softShadow(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            child: Tooltip(
              message: subtitle,
              child: const Text(
                title,
                style: TextStyle(
                  color: AppColors.subText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          _PreviewSection(color: color),
          _PanelDivider(),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _SwatchSection(
                    title: '최근 색상',
                    colors: recentColors,
                    selectedColor: color,
                    onSelect: onColorChange,
                  ),
                  _PanelDivider(),
                  _SwatchSection(
                    title: '기본 색상',
                    colors: colors,
                    selectedColor: color,
                    onSelect: onColorChange,
                  ),
                  _PanelDivider(),
                  _AdvancedColorSection(onTap: onAdvancedColorTap),
                  if (showFillOpacity) ...[
                    _PanelDivider(),
                    _TextFillAlphaInlineStrip(
                      alpha: alpha,
                      transparencyPct: transparencyPct,
                      onChanged: onTextFillAlphaChanged!,
                      onDragStart: onTextFillAlphaDragStart,
                      onChangeEnd: onTextFillAlphaChangeEnd,
                      onNumericTap: onTextFillAlphaValueTap == null
                          ? null
                          : () => onTextFillAlphaValueTap!(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.subText),
            tooltip: '닫기',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

/// 채움 투명도: 고급 색상 오른쪽 — 라벨 · 숫자(탭 입력) · 슬라이더
class _TextFillAlphaInlineStrip extends StatelessWidget {
  final double alpha;
  final int transparencyPct;
  final ValueChanged<double> onChanged;
  final VoidCallback? onDragStart;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onNumericTap;

  const _TextFillAlphaInlineStrip({
    required this.alpha,
    required this.transparencyPct,
    required this.onChanged,
    this.onDragStart,
    this.onChangeEnd,
    this.onNumericTap,
  });

  static const _kNum = TextStyle(
    color: AppColors.subText,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.subText,
  );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 220),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '투명',
            style: TextStyle(
              color: AppColors.subText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          if (onNumericTap != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onNumericTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('$transparencyPct', style: _kNum),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '$transparencyPct',
                style: const TextStyle(
                  color: AppColors.subText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: _materialsToolbarSliderTheme(context, thumbRadius: 6),
              child: Slider(
                value: alpha,
                min: 0,
                max: 1,
                onChangeStart: (_) => onDragStart?.call(),
                onChanged: onChanged,
                onChangeEnd: (_) => onChangeEnd?.call(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DockToolbarSlider extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String Function(double value)? format;
  final VoidCallback? onValueTap;
  final int flex;
  /// When false, returns the inner [Row] only; parent must supply horizontal bounds
  /// (e.g. [Expanded]).
  final bool expandInParent;

  const _DockToolbarSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.format,
    this.onValueTap,
    this.flex = 5,
    this.expandInParent = true,
  });

  @override
  Widget build(BuildContext context) {
    const titleSlotWidth = 26.0;
    const valueSlotWidth = 30.0;
    const labelToValueGap = 2.0;
    final label = format?.call(value) ?? value.toStringAsFixed(1);
    const tapStyle = TextStyle(
      color: AppColors.subText,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.subText,
    );
    const idleStyle = TextStyle(
      color: AppColors.subText,
      fontSize: 10,
      fontWeight: FontWeight.w800,
    );
    final inner = Row(
      children: [
        SizedBox(
          width: titleSlotWidth,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.subText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        SizedBox(width: labelToValueGap),
        SizedBox(
          width: valueSlotWidth,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onValueTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: onValueTap != null ? tapStyle : idleStyle,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: _materialsToolbarSliderTheme(context, thumbRadius: 5),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ],
    );
    if (!expandInParent) return inner;
    return Expanded(flex: flex, child: inner);
  }
}

class _WidthOnlyDockPanel extends StatelessWidget {
  final _ToolType tool;
  final double width;
  final double opacity;
  final int laserDismissMs;
  final ValueChanged<int> onLaserDismissMsChanged;
  final ValueChanged<double> onWidthChange;
  final ValueChanged<double> onWidthChangeEnd;
  final ValueChanged<double> onOpacityChange;
  final ValueChanged<double> onOpacityChangeEnd;
  final void Function(BuildContext panelContext) onWidthValueTap;
  final void Function(BuildContext panelContext) onOpacityValueTap;
  final VoidCallback onClose;

  const _WidthOnlyDockPanel({
    required this.tool,
    required this.width,
    required this.opacity,
    required this.laserDismissMs,
    required this.onLaserDismissMsChanged,
    required this.onWidthChange,
    required this.onWidthChangeEnd,
    required this.onOpacityChange,
    required this.onOpacityChangeEnd,
    required this.onWidthValueTap,
    required this.onOpacityValueTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (tool) {
      _ToolType.highlighter => '선 두께와 형광 투명도',
      _ToolType.eraser => '픽셀 지우개 크기',
      _ToolType.text => '',
      _ToolType.laser => '레이저 두께와 흔적 사라짐 시간',
      _ => '선 두께',
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
        boxShadow: softShadow(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (tool == _ToolType.pen || tool == _ToolType.pencil)
            _DockToolbarSlider(
              title: '두께',
              value: width,
              min: 1,
              max: 14,
              divisions: 26,
              onChanged: onWidthChange,
              onChangeEnd: onWidthChangeEnd,
              onValueTap: () => onWidthValueTap(context),
              flex: 10,
            ),
          if (tool == _ToolType.highlighter) ...[
            _DockToolbarSlider(
              title: '두께',
              value: width,
              min: 1,
              max: 14,
              divisions: 26,
              onChanged: onWidthChange,
              onChangeEnd: onWidthChangeEnd,
              onValueTap: () => onWidthValueTap(context),
              flex: 5,
            ),
            const SizedBox(width: 8),
            _DockToolbarSlider(
              title: '투명',
              value: opacity,
              min: 0.05,
              max: 1,
              divisions: 19,
              onChanged: onOpacityChange,
              onChangeEnd: onOpacityChangeEnd,
              format: (value) => '${(value * 100).round()}',
              onValueTap: () => onOpacityValueTap(context),
              flex: 5,
            ),
          ],
          if (tool == _ToolType.laser)
            Expanded(
              child: Tooltip(
                message: subtitle,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final sliderW = math
                        .min(200.0, c.maxWidth * 0.42)
                        .clamp(118.0, 220.0);
                    return Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: sliderW,
                          child: _DockToolbarSlider(
                            title: '두께',
                            value: width.clamp(3, 8),
                            min: 3,
                            max: 8,
                            divisions: 5,
                            onChanged: onWidthChange,
                            onChangeEnd: onWidthChangeEnd,
                            onValueTap: () => onWidthValueTap(context),
                            expandInParent: false,
                            flex: 10,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '사라짐',
                              style: TextStyle(
                                color: AppColors.subText,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _LaserMiniChip(
                              label: '0.5초',
                              selected: laserDismissMs == 500,
                              onTap: () => onLaserDismissMsChanged(500),
                            ),
                            _LaserMiniChip(
                              label: '0.8초',
                              selected: laserDismissMs == 800,
                              onTap: () => onLaserDismissMsChanged(800),
                            ),
                            _LaserMiniChip(
                              label: '1.0초',
                              selected: laserDismissMs == 1000,
                              onTap: () => onLaserDismissMsChanged(1000),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          if (tool == _ToolType.eraser)
            Expanded(
              flex: 10,
              child: Tooltip(
                message: subtitle,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onWidthValueTap(context),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            width.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.navy,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: _materialsToolbarSliderTheme(
                          context,
                          thumbRadius: 5,
                        ),
                        child: Slider(
                          value: width.clamp(1, 14),
                          min: 1,
                          max: 14,
                          divisions: 26,
                          onChanged: onWidthChange,
                          onChangeEnd: onWidthChangeEnd,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.subText),
            tooltip: '닫기',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}

class _LaserMiniChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LaserMiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Material(
        color: selected
            ? AppColors.blue.withValues(alpha: 0.14)
            : AppColors.graySoft,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.blue : AppColors.subText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.line,
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final Color color;

  const _PreviewSection({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '현재',
          style: TextStyle(
            color: AppColors.subText,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.line),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _hexFromColor(color),
          style: const TextStyle(
            color: AppColors.subText,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SwatchLabel extends StatelessWidget {
  final String text;

  const _SwatchLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.subText,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SwatchSection extends StatelessWidget {
  final String title;
  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onSelect;

  const _SwatchSection({
    required this.title,
    required this.colors,
    required this.selectedColor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SwatchLabel(text: title == '최근 색상' ? '최근' : '기본'),
        const SizedBox(width: 6),
        if (colors.isEmpty)
          const Text(
            '-',
            style: TextStyle(
              color: AppColors.subText,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: colors
                .map(
                  (swatch) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _ColorDot(
                      color: swatch,
                      active: swatch.toARGB32() == selectedColor.toARGB32(),
                      onTap: () => onSelect(swatch),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        foregroundColor: AppColors.subText,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AdvancedColorSection extends StatelessWidget {
  final VoidCallback onTap;

  const _AdvancedColorSection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _QuickActionButton(label: '고급 색상', onTap: onTap);
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.blue : AppColors.line,
            width: active ? 2 : 1,
          ),
          boxShadow: active ? softShadow() : null,
        ),
      ),
    );
  }
}

class _ColorSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String Function(double value)? valueFormatter;
  final VoidCallback? onValueTap;

  const _ColorSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.valueFormatter,
    this.onValueTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueFormatter?.call(value) ?? value.toStringAsFixed(2);
    const tapStyle = TextStyle(
      color: AppColors.subText,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.subText,
    );
    const idleStyle = TextStyle(
      color: AppColors.subText,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.subText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: onValueTap == null
                ? Text(
                    display,
                    textAlign: TextAlign.center,
                    style: idleStyle,
                  )
                : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onValueTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        child: Text(
                          display,
                          textAlign: TextAlign.center,
                          style: tapStyle,
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: SliderTheme(
              data: _materialsToolbarSliderTheme(context, thumbRadius: 6),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AaToolButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _AaToolButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 42,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSoft : AppColors.graySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.blue : AppColors.line),
        ),
        alignment: Alignment.center,
        child: Text(
          'Aa',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: active ? AppColors.blue : AppColors.navy,
          ),
        ),
      ),
    );
  }
}

class _CompactToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? tooltip;

  const _CompactToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final body = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 42,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSoft : AppColors.graySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.blue : AppColors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? AppColors.blue : AppColors.navy,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: active ? AppColors.blue : AppColors.subText,
              ),
            ),
          ],
        ),
      ),
    );
    final t = tooltip;
    if (t != null && t.isNotEmpty) {
      return Tooltip(message: t, child: body);
    }
    return body;
  }
}

class _ToolbarColorButton extends StatelessWidget {
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarColorButton({
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: 44,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarValueChip extends StatelessWidget {
  final String label;
  final String value;

  const _ToolbarValueChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.graySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.subText,
        ),
      ),
    );
  }
}

class _ToolbarModeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ToolbarModeChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.subText,
            ),
          ),
        ),
      ),
    );
  }
}
