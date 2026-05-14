part of 'materials_page.dart';

// ── PDF BACKGROUND ───────────────────────────────────────────────

class _PdfCanvasBackground extends StatefulWidget {
  final String pdfPath;
  final int pageIndex;
  final BoxFit boxFit;

  /// Decode width for pdfx render; height follows page aspect. Capped for memory.
  final int maxRenderWidth;

  const _PdfCanvasBackground({
    required this.pdfPath,
    required this.pageIndex,
    this.boxFit = BoxFit.contain,
    this.maxRenderWidth = 1024,
  });

  @override
  State<_PdfCanvasBackground> createState() => _PdfCanvasBackgroundState();
}

class _PdfCanvasBackgroundState extends State<_PdfCanvasBackground> {
  late Future<_PdfRenderResult?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _renderPage(
      widget.pdfPath,
      widget.pageIndex,
      widget.maxRenderWidth,
    );
  }

  @override
  void didUpdateWidget(covariant _PdfCanvasBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.maxRenderWidth != widget.maxRenderWidth) {
      // didUpdateWidget is followed by build; update future directly to avoid
      // re-entrant setState during rapid page transitions.
      _imageFuture = _renderPage(
        widget.pdfPath,
        widget.pageIndex,
        widget.maxRenderWidth,
      );
    }
  }

  Future<_PdfRenderResult?> _renderPage(
    String path,
    int pageIndex,
    int maxWidth,
  ) async {
    PdfDocument? document;
    PdfPage? page;
    try {
      await _ensurePdfxRegistration();
      document = await PdfDocument.openFile(path);
      final totalPages = document.pagesCount;
      final safeIndex = pageIndex.clamp(0, totalPages - 1);
      page = await document.getPage(safeIndex + 1);
      final w = maxWidth.clamp(320, 1400);
      final image = await page.render(
        width: w.toDouble(),
        height: (w * page.height / page.width).toInt().toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      return _PdfRenderResult(bytes: image?.bytes, totalPages: totalPages);
    } catch (_) {
      return null;
    } finally {
      await page?.close();
      await document?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PdfRenderResult?>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final result = snapshot.data;
        final bytes = result?.bytes;
        if (bytes == null) {
          return Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: const Text(
              'PDF 미리보기를 불러오지 못했어요',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.subText,
              ),
            ),
          );
        }
        return ColoredBox(
          color: Colors.white,
          child: SizedBox.expand(
            child: Image.memory(
              bytes,
              fit: widget.boxFit,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}

class _PdfRenderResult {
  final Uint8List? bytes;
  final int totalPages;
  const _PdfRenderResult({required this.bytes, required this.totalPages});
}
