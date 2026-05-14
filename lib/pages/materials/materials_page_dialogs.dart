part of 'materials_page.dart';

// ── DIALOG HELPERS ─────────────────────────────────────────────────
//
// Self-managed controllers prevent "controller used after dispose" crashes
// during the dialog's exit animation.

class _TextEditDialog extends StatefulWidget {
  final String initialText;

  const _TextEditDialog({required this.initialText});

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('텍스트 편집'),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        decoration: const InputDecoration(hintText: '내용'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('적용'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String initial;

  const _RenameDialog({
    required this.title,
    required this.hint,
    required this.initial,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('확인')),
      ],
    );
  }
}

/// Centered on the memo editing viewport (outside canvas zoom); horizontal preview strip.
class _MemoPageNavigatorRouteBody extends StatefulWidget {
  const _MemoPageNavigatorRouteBody({
    required this.boardRect,
    required this.pages,
    required this.paperStyle,
    required this.pdfDisplayMode,
    required this.pdfs,
    required this.pageCount,
    required this.currentIndex,
    required this.pageHints,
    required this.liveCanvasSize,
    required this.jumpController,
    required this.onSelectIndex,
    required this.onPrevPage,
    required this.onNextPage,
    required this.onSubmitJump,
  });

  final Rect? boardRect;
  final List<_CanvasPage> pages;
  final _PaperStyle paperStyle;
  final _PdfDisplayMode pdfDisplayMode;
  final List<_PdfAsset> pdfs;
  final int pageCount;
  final int currentIndex;
  final List<bool> pageHints;
  /// Pixel size of the editor's current document canvas — strokes are stored
  /// in this coordinate frame, so previews must paint at the same size and
  /// rely on [FittedBox] to scale the result down into a thumbnail.
  final Size liveCanvasSize;
  final TextEditingController jumpController;
  final void Function(int index) onSelectIndex;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final void Function(String raw) onSubmitJump;

  @override
  State<_MemoPageNavigatorRouteBody> createState() =>
      _MemoPageNavigatorRouteBodyState();
}

class _MemoPageNavigatorRouteBodyState extends State<_MemoPageNavigatorRouteBody> {
  late final ScrollController _previewScroll;
  bool _didAlignPreview = false;
  bool _scheduledAlign = false;
  int _alignAttempts = 0;

  @override
  void initState() {
    super.initState();
    _previewScroll = ScrollController();
  }

  @override
  void dispose() {
    _previewScroll.dispose();
    super.dispose();
  }

  void _alignPreviewOnce(double stride, double cardW, double pad, double innerW) {
    if (_didAlignPreview || !mounted) return;
    if (!_previewScroll.hasClients) {
      if (_alignAttempts++ > 14) {
        _didAlignPreview = true;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _alignPreviewOnce(stride, cardW, pad, innerW);
      });
      return;
    }
    final vp = _previewScroll.position.viewportDimension;
    final idx = widget.currentIndex.clamp(0, widget.pageCount - 1);
    final target = idx * stride - vp / 2 + cardW / 2 + pad;
    final max = _previewScroll.position.maxScrollExtent;
    _previewScroll.jumpTo(target.clamp(0.0, max));
    _didAlignPreview = true;
  }

  ({double cardW, double cardH, double stride, int count, double pad})
  _computeStripLayout(double innerW) {
    const spacing = 14.0;
    const pad = 12.0;
    const kAspect = 1 / 1.414;
    final avail = math.max(40.0, innerW - pad * 2);
    var count = 8;
    var cardH = 160.0;
    var cardW = cardH * kAspect;
    var slot = cardW + spacing;
    count = (avail / slot).floor().clamp(6, 10);
    if (widget.pageCount < count) {
      count = widget.pageCount;
    }
    if (count < 1) count = 1;
    cardW = (avail - spacing * math.max(0, count - 1)) / count;
    cardH = cardW / kAspect;
    if (cardH > 170) {
      cardH = 170;
      cardW = cardH * kAspect;
    }
    if (cardH < 150 && count > 1) {
      cardH = 150;
      cardW = cardH * kAspect;
      count = ((avail + spacing) / (cardW + spacing)).floor().clamp(1, 10);
      if (widget.pageCount < count) count = widget.pageCount;
      if (count < 1) count = 1;
      cardW = (avail - spacing * math.max(0, count - 1)) / count;
      cardH = cardW / kAspect;
      cardH = cardH.clamp(150.0, 170.0);
      cardW = cardH * kAspect;
    }
    final stride = cardW + spacing;
    return (cardW: cardW, cardH: cardH, stride: stride, count: count, pad: pad);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final br = widget.boardRect;
    const margin = 8.0;
    final availW = br != null ? (br.width - margin * 2).clamp(0.0, double.infinity) : 0.0;
    final dialogW = (br != null && br.width > 24)
        ? math.min(720.0, math.max(220.0, availW))
        : (size.width * 0.88).clamp(280.0, 720.0);
    final cx = (br != null && br.width > 0) ? br.center.dx : size.width * 0.5;
    final cy = (br != null && br.height > 0) ? br.center.dy : size.height * 0.48;
    final left = () {
      if (br != null && br.width > 24) {
        final lo = br.left + margin;
        final hi = br.right - dialogW - margin;
        if (hi < lo) return lo;
        return (cx - dialogW / 2).clamp(lo, hi);
      }
      return (cx - dialogW / 2).clamp(margin, size.width - dialogW - margin);
    }();
    const estH = 430.0;
    final top = () {
      if (br != null && br.height > 24) {
        final lo = br.top + margin;
        final hi = br.bottom - estH - margin;
        if (hi < lo) return lo;
        return (cy - estH / 2).clamp(lo, hi);
      }
      return (cy - estH / 2).clamp(
        mq.padding.top + margin,
        size.height - estH - mq.padding.bottom - margin,
      );
    }();
    final cur = widget.currentIndex;
    final n = widget.pageCount;

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: dialogW,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: size.height * 0.88,
                  maxWidth: dialogW,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                    boxShadow: softShadow(),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + mq.viewInsets.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '페이지 이동',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '현재 ${cur + 1} / $n',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.subText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              onPressed: cur > 0 ? widget.onPrevPage : null,
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              onPressed: cur < n - 1 ? widget.onNextPage : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '특정 페이지로',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.subText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: widget.jumpController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '페이지 번호 (1–$n)',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => widget.onSubmitJump(
                                  widget.jumpController.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: () => widget.onSubmitJump(
                                widget.jumpController.text,
                              ),
                              child: const Text('이동'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '페이지 미리보기',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.subText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, c) {
                            final geom = _computeStripLayout(c.maxWidth);
                            if (!_scheduledAlign) {
                              _scheduledAlign = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _alignPreviewOnce(
                                  geom.stride,
                                  geom.cardW,
                                  geom.pad,
                                  c.maxWidth,
                                );
                              });
                            }
                            return SizedBox(
                              height: geom.cardH + 26,
                              child: ListView.separated(
                                controller: _previewScroll,
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.symmetric(
                                  horizontal: geom.pad,
                                ),
                                itemCount: n,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (ctx, i) {
                                  final sel = i == cur;
                                  final hint = i < widget.pageHints.length
                                      ? widget.pageHints[i]
                                      : false;
                                  final page = widget.pages[i];
                                  final pdf =
                                      _memoNavigatorPdfAsset(widget.pdfs, page);
                                  final hasRaster = pdf != null ||
                                      (page.sourceImagePath != null &&
                                          page.sourceImagePath!.isNotEmpty);
                                  final pdfIdx = pdf != null
                                      ? _memoNavigatorPdfPageIndex(pdf, page)
                                      : 0;
                                  return GestureDetector(
                                    onTap: () => widget.onSelectIndex(i),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      curve: Curves.easeOutCubic,
                                      width: geom.cardW,
                                      height: geom.cardH,
                                      decoration: BoxDecoration(
                                        color: AppColors.cardAlt,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: sel
                                              ? AppColors.blue
                                              : AppColors.line,
                                          width: sel ? 2.4 : 1,
                                        ),
                                        boxShadow: sel
                                            ? [
                                                BoxShadow(
                                                  color: AppColors.blue
                                                      .withValues(alpha: 0.28),
                                                  blurRadius: 10,
                                                  spreadRadius: 0,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    _MemoPageNavigatorPreview(
                                                      page: page,
                                                      paperStyle:
                                                          widget.paperStyle,
                                                      pdfDisplayMode:
                                                          widget.pdfDisplayMode,
                                                      pdfAsset: pdf,
                                                      pdfPageIndex: pdfIdx,
                                                      importBgPath:
                                                          page.sourceImagePath,
                                                      hasRasterBackground:
                                                          hasRaster,
                                                      liveCanvasSize:
                                                          widget.liveCanvasSize,
                                                    ),
                                                    if (hint)
                                                      Align(
                                                        alignment:
                                                            Alignment.topCenter,
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(top: 6),
                                                          child: Container(
                                                            height: 3,
                                                            width: geom.cardW *
                                                                0.42,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: AppColors
                                                                  .blue
                                                                  .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                2,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 5,
                                            ),
                                            child: Text(
                                              '${i + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: sel
                                                    ? AppColors.blue
                                                    : AppColors.navy,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Owns a [FocusNode] so [_CanvasTextObjectView] can be used read-only in previews.
class _NavigatorPreviewTextHost extends StatefulWidget {
  final _CanvasTextBox box;
  final Size canvasSize;

  const _NavigatorPreviewTextHost({
    required this.box,
    required this.canvasSize,
  });

  @override
  State<_NavigatorPreviewTextHost> createState() =>
      _NavigatorPreviewTextHostState();
}

class _NavigatorPreviewTextHostState extends State<_NavigatorPreviewTextHost> {
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CanvasTextObjectView(
      box: widget.box,
      canvasSize: widget.canvasSize,
      textToolActive: false,
      selected: false,
      editing: false,
      editController: null,
      editFocus: _focus,
    );
  }
}

/// Read-only scaled snapshot of a memo page for the page navigator strip.
///
/// The preview is sized in the **same pixel coordinates the editor uses** so
/// stroke geometry (which is stored as raw canvas-pixel offsets) lines up with
/// images and text. [FittedBox] downscales the whole tree to fit the card.
class _MemoPageNavigatorPreview extends StatelessWidget {
  final _CanvasPage page;
  final _PaperStyle paperStyle;
  final _PdfDisplayMode pdfDisplayMode;
  final _PdfAsset? pdfAsset;
  final int pdfPageIndex;
  final String? importBgPath;
  final bool hasRasterBackground;
  /// Editor's live document canvas size; matches the frame in which strokes
  /// were drawn.
  final Size liveCanvasSize;

  const _MemoPageNavigatorPreview({
    required this.page,
    required this.paperStyle,
    required this.pdfDisplayMode,
    required this.pdfAsset,
    required this.pdfPageIndex,
    required this.importBgPath,
    required this.hasRasterBackground,
    required this.liveCanvasSize,
  });

  BoxFit get _pdfFit =>
      pdfDisplayMode == _PdfDisplayMode.stretchToMemo ? BoxFit.fill : BoxFit.contain;

  @override
  Widget build(BuildContext context) {
    // Preserve A4 portrait aspect even if the live canvas measurement is
    // momentarily skewed (e.g. zero in early build frames).
    var w = liveCanvasSize.width;
    var h = liveCanvasSize.height;
    if (w <= 0 || h <= 0) {
      w = 360;
      h = w * 1.414;
    }
    final canvasSize = Size(w, h);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final sorted = page.placedImages.toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: RotatedBox(
          quarterTurns: page.canvasRotationQuarterTurns % 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (pdfAsset != null)
                _PdfCanvasBackground(
                  pdfPath: pdfAsset!.path,
                  pageIndex: pdfPageIndex,
                  boxFit: _pdfFit,
                  maxRenderWidth: 620,
                ),
              if (importBgPath != null && importBgPath!.isNotEmpty)
                ColoredBox(
                  color: Colors.white,
                  child: Image.file(
                    File(importBgPath!),
                    fit: _pdfFit,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _MemoBackgroundPainter(
                    paperStyle: paperStyle,
                    hasPdf: hasRasterBackground,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _StrokeAnnotationPainter(
                    strokes: page.strokes,
                    workingStroke: null,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              ...sorted.map((img) {
                final r = img.rect.toLocalRect(canvasSize);
                final cacheW = (r.width * dpr).round().clamp(1, 2048);
                final cacheH = (r.height * dpr).round().clamp(1, 2048);
                return Positioned(
                  left: r.left,
                  top: r.top,
                  width: r.width,
                  height: r.height,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: img.rotationRad,
                      alignment: Alignment.center,
                      child: Image.file(
                        File(img.storagePath),
                        fit: BoxFit.contain,
                        cacheWidth: cacheW,
                        cacheHeight: cacheH,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              for (final t in page.textBoxes)
                _NavigatorPreviewTextHost(
                  box: t,
                  canvasSize: canvasSize,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
