part of 'materials_page.dart';

// ── PAINTER ──────────────────────────────────────────────────────

/// Lasso accent color shared by both the drawing path and the selection
/// rectangle/handles so the live freehand stroke and the resulting selection
/// chrome read as a single UI element. Adjust here once for theming.
const Color _kLassoAccent = Color(0xFF2563EB);
const Color _kLassoAccentSoft = Color(0xFFB6CCFF);
const Color _kLassoHandleBorder = Color(0xFF1E40AF);

/// Inline text-box paddings shared by [_CanvasTextBox] geometry and the
/// editing [TextField]. Keep both edges of the calculation consistent so the
/// auto-grow height stays tight against the visible text.
const double _kTextInlineHorizontalPadding = 6;
const double _kTextInlineVerticalPadding = 4;

class _StudioOverlayPainter extends CustomPainter {
  final List<Offset>? lassoPath;
  final Rect? selectionBounds;
  final bool showResizeHandles;

  /// Selection rotation around [selectionBounds.center], in radians. The
  /// painter draws the bounds, handles, and chrome rotated by this angle so
  /// the box visibly tilts with its contents.
  final double selectionRotationRad;

  const _StudioOverlayPainter({
    required this.lassoPath,
    required this.selectionBounds,
    required this.showResizeHandles,
    this.selectionRotationRad = 0,
  });

  void _paintDashedPath(Canvas canvas, Path path, Paint paint) {
    const dash = 10.0;
    const gap = 6.0;
    var paintedAny = false;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      var draw = true;
      if (metric.length < (dash + gap) * 0.8) {
        canvas.drawPath(metric.extractPath(0, metric.length), paint);
        paintedAny = true;
        continue;
      }
      while (d < metric.length) {
        final len = draw ? dash : gap;
        final end = (d + len).clamp(0.0, metric.length);
        if (draw) {
          canvas.drawPath(metric.extractPath(d, end), paint);
          paintedAny = true;
        }
        d = end;
        draw = !draw;
      }
    }
    if (!paintedAny) {
      canvas.drawPath(path, paint);
    }
  }

  void _drawHandleSquare(Canvas canvas, Offset c, Paint fill, Paint stroke) {
    final r = Rect.fromCenter(
      center: c,
      width: _studioSelHandle,
      height: _studioSelHandle,
    );
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(1));
    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);
  }

  void _paintFabIcon(
    Canvas canvas,
    Rect outer,
    String glyph, {
    required Color glyphColor,
  }) {
    final bg = RRect.fromRectAndRadius(
      outer,
      const Radius.circular(5),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = const Color(0xD9161820),
    );
    canvas.drawRRect(
      bg,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: glyphColor,
          fontSize: outer.height > 26 ? 15 : 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        outer.center.dx - tp.width * 0.5,
        outer.center.dy - tp.height * 0.5,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pathPts = lassoPath;
    if (pathPts != null && pathPts.length >= 2) {
      final path = Path()..moveTo(pathPts.first.dx, pathPts.first.dy);
      for (var i = 1; i < pathPts.length; i++) {
        path.lineTo(pathPts[i].dx, pathPts[i].dy);
      }
      // Faint halo so the dashed accent reads on white and on PDF backgrounds.
      final haloPath = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, haloPath);
      final stroke = Paint()
        ..color = _kLassoAccent.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      _paintDashedPath(canvas, path, stroke);
    }

    final sel = selectionBounds;
    if (sel != null) {
      // Rotated overlay: render the box, handles, and chrome around the
      // bounds' center so the rectangle visibly tilts with its contents.
      canvas.save();
      canvas.translate(sel.center.dx, sel.center.dy);
      if (selectionRotationRad != 0) {
        canvas.rotate(selectionRotationRad);
      }
      canvas.translate(-sel.center.dx, -sel.center.dy);

      final halo = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawRect(sel.inflate(0.5), halo);

      final border = Paint()
        ..color = _kLassoAccent.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25;
      canvas.drawRect(sel, border);

      if (showResizeHandles) {
        final fill = Paint()..color = Colors.white;
        final stroke = Paint()
          ..color = _kLassoHandleBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        final pts = <Offset>[
          sel.topLeft,
          Offset(sel.center.dx, sel.top),
          sel.topRight,
          Offset(sel.right, sel.center.dy),
          sel.bottomRight,
          Offset(sel.center.dx, sel.bottom),
          sel.bottomLeft,
          Offset(sel.left, sel.center.dy),
        ];
        for (final p in pts) {
          _drawHandleSquare(canvas, p, fill, stroke);
        }
      }

      final rotC = _studioRotateKnobCenter(sel);
      final rotR = _studioSelRotateR;
      canvas.drawCircle(
        rotC,
        rotR,
        Paint()..color = _kLassoAccent,
      );
      canvas.drawCircle(
        rotC,
        rotR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      final rotTp = TextPainter(
        text: TextSpan(
          text: '↻',
          style: TextStyle(
            color: Colors.white,
            fontSize: rotR * 1.05,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      rotTp.paint(
        canvas,
        Offset(rotC.dx - rotTp.width * 0.5, rotC.dy - rotTp.height * 0.5),
      );

      final copyOuter = _studioSelectionCopyFabRect(sel);
      final delOuter = _studioSelectionDeleteFabRect(sel);
      _paintFabIcon(canvas, copyOuter, '⎘', glyphColor: _kLassoAccentSoft);
      _paintFabIcon(canvas, delOuter, '×', glyphColor: const Color(0xFFF87171));

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _StudioOverlayPainter oldDelegate) {
    if (lassoPath != null || oldDelegate.lassoPath != null) return true;
    final a = lassoPath;
    final b = oldDelegate.lassoPath;
    if (!identical(a, b)) {
      if (a == null || b == null || a.length != b.length) return true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return true;
      }
    }
    return oldDelegate.selectionBounds != selectionBounds ||
        oldDelegate.showResizeHandles != showResizeHandles ||
        oldDelegate.selectionRotationRad != selectionRotationRad;
  }
}

void _paintMemoStrokeOnCanvas(Canvas canvas, _Stroke stroke) {
  final points = stroke.points;
  if (points.length < 2) return;
  if (!_strokeToolIsPersistedInk(stroke.tool)) return;

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke.width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..blendMode = BlendMode.srcOver
    ..color = stroke.color;

  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (int i = 1; i < points.length; i++) {
    final prev = points[i - 1];
    final curr = points[i];
    final mx = (prev.dx + curr.dx) / 2;
    final my = (prev.dy + curr.dy) / 2;
    path.quadraticBezierTo(prev.dx, prev.dy, mx, my);
  }

  canvas.drawPath(path, paint);
}

/// Paper / grid behind PDF and annotations. Does not participate in stroke
/// erase layers so PDF pixels are never touched by BlendMode.clear.
class _MemoBackgroundPainter extends CustomPainter {
  final _PaperStyle paperStyle;
  final bool hasPdf;

  const _MemoBackgroundPainter({
    required this.paperStyle,
    required this.hasPdf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!hasPdf) {
      canvas.drawRect(Offset.zero & size, Paint()..color = _memoPaperColor);
    }

    switch (paperStyle) {
      case _PaperStyle.ruled:
        _paintRuled(canvas, size);
        break;
      case _PaperStyle.grid:
        _paintGrid(canvas, size);
        break;
      case _PaperStyle.plain:
        break;
    }
  }

  void _paintRuled(Canvas canvas, Size size) {
    const gap = 28.0;
    final p = Paint()
      ..color = _memoRuleColor
      ..strokeWidth = 1;
    for (double y = gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final margin = Paint()
      ..color = _memoMarginColor
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(52, 0), Offset(52, size.height), margin);
  }

  void _paintGrid(Canvas canvas, Size size) {
    const gap = 24.0;
    final p = Paint()
      ..color = _memoRuleColor
      ..strokeWidth = 0.9;
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _MemoBackgroundPainter oldDelegate) {
    return oldDelegate.paperStyle != paperStyle || oldDelegate.hasPdf != hasPdf;
  }
}

/// User strokes only (isolated [saveLayer] for consistent blending).
class _StrokeAnnotationPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? workingStroke;

  const _StrokeAnnotationPainter({
    required this.strokes,
    required this.workingStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layerBounds = Offset.zero & size;
    canvas.saveLayer(layerBounds, Paint());
    for (final stroke in strokes) {
      _paintMemoStrokeOnCanvas(canvas, stroke);
    }
    if (workingStroke != null) {
      _paintMemoStrokeOnCanvas(canvas, workingStroke!);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StrokeAnnotationPainter oldDelegate) {
    // Strokes are sometimes mutated in place (lasso move). List / working
    // reference equality can stay identical while geometry changes.
    return true;
  }
}

/// Debug: raw listener local vs clamped document (should overlap after fix).
class _TouchAlignmentDebugPainter extends CustomPainter {
  final Offset? touchDoc;
  final Offset? appliedDoc;

  const _TouchAlignmentDebugPainter({
    required this.touchDoc,
    required this.appliedDoc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = touchDoc;
    final a = appliedDoc;
    if (t == null || a == null) return;
    canvas.drawCircle(
      t,
      10,
      Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      a,
      6,
      Paint()
        ..color = Colors.deepPurpleAccent.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TouchAlignmentDebugPainter oldDelegate) {
    return oldDelegate.touchDoc != touchDoc || oldDelegate.appliedDoc != appliedDoc;
  }
}

/// Ephemeral presentation laser — not persisted as strokes.
class _LaserOverlayPainter extends CustomPainter {
  /// 0 = dot, 1 = trail.
  final int modeIndex;
  final List<Offset> trailPoints;
  final Offset? dotDoc;
  final Color color;
  /// User "두께" for trail (px), clamped upstream to ~3–8.
  final double trailStrokeWidth;
  final double trailOpacity;

  /// Bumped with `_laserRepaint` whenever geometry/opacity changes so
  /// [shouldRepaint] stays correct even if lists were shared by reference.
  final int repaintVersion;

  _LaserOverlayPainter({
    required this.modeIndex,
    required this.trailPoints,
    required this.dotDoc,
    required this.color,
    required this.trailStrokeWidth,
    required this.trailOpacity,
    required this.repaintVersion,
  });

  double get _dotDiameter =>
      12.0 + (trailStrokeWidth.clamp(3.0, 8.0) - 3.0) / 5.0 * 6.0;

  double _a(double v) => (v * trailOpacity).clamp(0.0, 1.0);

  void _paintDot(Canvas canvas, Offset c) {
    final radius = _dotDiameter * 0.5;
    for (var pass = 2; pass >= 0; pass--) {
      final r = radius * (1.35 + pass * 0.55);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: _a(0.07 + pass * 0.05))
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    for (var pass = 3; pass >= 0; pass--) {
      final r = radius * (0.92 + pass * 0.42);
      final baseA = (0.14 + pass * 0.2) * color.a;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color.withValues(alpha: _a(baseA.clamp(0.0, 1.0)))
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(
      c,
      radius * 0.38,
      Paint()
        ..color = color.withValues(alpha: _a((color.a * 0.98).clamp(0.0, 1.0)))
        ..style = PaintingStyle.fill,
    );
  }

  void _paintTrail(Canvas canvas) {
    final pts = trailPoints;
    if (pts.isEmpty) return;
    final wUser = trailStrokeWidth.clamp(3.0, 8.0);
    final coreW = math.max(2.4, wUser * 0.52);
    if (pts.length == 1) {
      _paintDot(canvas, pts.first);
      return;
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    for (var pass = 2; pass >= 0; pass--) {
      final w = wUser * (1.25 + pass * 0.75);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: _a(0.05 + pass * 0.045))
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.5),
      );
    }
    for (var pass = 3; pass >= 0; pass--) {
      final w = wUser * (0.95 + pass * 0.72);
      final baseA = (color.a * (0.11 + pass * 0.18)).clamp(0.0, 1.0);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: _a(baseA))
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: _a((color.a * 0.97).clamp(0.0, 1.0)))
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (modeIndex == 0) {
      final d = dotDoc;
      if (d != null) _paintDot(canvas, d);
      return;
    }
    _paintTrail(canvas);
  }

  @override
  bool shouldRepaint(covariant _LaserOverlayPainter oldDelegate) {
    if (oldDelegate.repaintVersion != repaintVersion) return true;
    if (modeIndex != oldDelegate.modeIndex) return true;
    if (dotDoc != oldDelegate.dotDoc) return true;
    if (trailOpacity != oldDelegate.trailOpacity) return true;
    if (trailPoints.length != oldDelegate.trailPoints.length) return true;
    for (var i = 0; i < trailPoints.length; i++) {
      if (i >= oldDelegate.trailPoints.length ||
          trailPoints[i] != oldDelegate.trailPoints[i]) {
        return true;
      }
    }
    return color != oldDelegate.color ||
        trailStrokeWidth != oldDelegate.trailStrokeWidth;
  }
}
