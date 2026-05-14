part of 'materials_page.dart';

// ── DATA CLASSES ─────────────────────────────────────────────────

class _PdfAsset {
  final String id;
  final String name;
  final String path;
  final int addedAtMillis;

  /// 업로드 시 측정. 없으면 화면에서 파일을 다시 열어 쪽수를 읽습니다.
  final int? pageCount;

  const _PdfAsset({
    required this.id,
    required this.name,
    required this.path,
    required this.addedAtMillis,
    this.pageCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'addedAtMillis': addedAtMillis,
    'pageCount': pageCount,
  };

  factory _PdfAsset.fromJson(Map<String, dynamic> json) => _PdfAsset(
    id: _mpString(json, 'id'),
    name: _mpString(json, 'name'),
    path: _mpString(json, 'path'),
    addedAtMillis: _mpInt(json, 'addedAtMillis', 0),
    pageCount: (json['pageCount'] as num?)?.toInt(),
  );
}

class _CanvasPage {
  /// Stable id for persistence / future sync (not list index).
  final String id;
  final List<_Stroke> strokes;
  final List<Object> redoStack;
  final List<_PlacedImage> placedImages;
  final List<_CanvasTextBox> textBoxes;

  /// Stroke markers + lasso layout snapshots, chronological (oldest → newest).
  final List<Object> unifiedUndo;

  _CanvasPageKind kind;

  /// When [kind] is [pdf]: asset id in [_uploadedPdfs].
  String? sourcePdfId;

  /// When [kind] is [pdf]: 0-based page index inside that PDF file.
  int? sourcePdfPageIndex;

  /// When [kind] is [importedImage]: full-page background image file path.
  String? sourceImagePath;

  /// 0–3 quarter turns for this page only (see [RotatedBox] on main canvas).
  int canvasRotationQuarterTurns;

  _CanvasPage({
    String? id,
    this.kind = _CanvasPageKind.memo,
    this.sourcePdfId,
    this.sourcePdfPageIndex,
    this.sourceImagePath,
    this.canvasRotationQuarterTurns = 0,
    List<_Stroke>? strokes,
    List<Object>? redoStack,
    List<_PlacedImage>? placedImages,
    List<_CanvasTextBox>? textBoxes,
    List<Object>? unifiedUndo,
  }) : id = id ?? Uuid().v4(),
       strokes = strokes ?? [],
       redoStack = redoStack ?? [],
       placedImages = placedImages ?? [],
       textBoxes = textBoxes ?? [],
       unifiedUndo = unifiedUndo ?? [];

  /// Blank ruled/grid/plain memo — never shares PDF render state.
  factory _CanvasPage.createDefaultMemoPage() {
    return _CanvasPage(
      kind: _CanvasPageKind.memo,
      sourcePdfId: null,
      sourcePdfPageIndex: null,
      sourceImagePath: null,
    );
  }

  factory _CanvasPage.createPdfCanvasPage({
    required String pdfAssetId,
    required int pdfPageIndex,
  }) {
    return _CanvasPage(
      kind: _CanvasPageKind.pdf,
      sourcePdfId: pdfAssetId,
      sourcePdfPageIndex: pdfPageIndex,
      sourceImagePath: null,
    );
  }

  static const int _maxUnifiedUndo = 100;

  void _trimUnifiedUndo() {
    while (unifiedUndo.length > _maxUnifiedUndo) {
      unifiedUndo.removeAt(0);
    }
  }

  void addStroke(_Stroke stroke) {
    if (!_strokeToolIsPersistedInk(stroke.tool)) return;
    strokes.add(stroke);
    redoStack.clear();
    unifiedUndo.add(_StrokeUndoMarker());
    _trimUnifiedUndo();
  }

  void pushLayoutUndo(_LassoLayoutSnapshot snapshot) {
    unifiedUndo.add(snapshot);
    redoStack.clear();
    _trimUnifiedUndo();
  }

  void pushPageVisualUndo(_PageVisualStateSnapshot snapshot) {
    unifiedUndo.add(snapshot);
    redoStack.clear();
    _trimUnifiedUndo();
  }

  /// Session undo stack for this page only (not persisted in JSON).
  bool get canUndo => unifiedUndo.isNotEmpty;

  /// Redo stack for this page only.
  bool get canRedo => redoStack.isNotEmpty;

  void removeStrokesIntersecting(
    List<Offset> eraserPoints, [
    double radius = 10,
  ]) {
    if (eraserPoints.isEmpty) return;
    unifiedUndo.add(_StrokeListSnapshotUndo.fromStrokes(strokes));
    redoStack.clear();
    removeStrokesIntersectingDestructive(eraserPoints, radius);
    _trimUnifiedUndo();
  }

  /// Same geometry as [removeStrokesIntersecting] without touching undo/redo.
  /// Used while a stroke-eraser gesture is in progress.
  void removeStrokesIntersectingDestructive(
    List<Offset> eraserPoints, [
    double radius = 10,
  ]) {
    if (eraserPoints.isEmpty) return;
    strokes.removeWhere(
      (s) => s.tool == _ToolType.eraser || s.tool == _ToolType.laser,
    );
    final eraserBounds = _eraserPolylineBounds(
      eraserPoints,
    ).inflate(radius + 80.0);
    strokes.removeWhere((stroke) {
      if (!_strokeToolIsPersistedInk(stroke.tool)) return false;
      final threshold = radius + (stroke.width * 0.5);
      final strokeBounds = _MaterialsPageState._strokePixelBounds(
        stroke,
      ).inflate(threshold + 14.0);
      if (!strokeBounds.overlaps(eraserBounds)) return false;
      return _strokeIntersectsPath(stroke, eraserPoints, radius);
    });
  }

  void replaceStrokesFromUndoSnapshot(_StrokeListSnapshotUndo snap) {
    strokes
      ..clear()
      ..addAll(
        snap.strokesJson
            .map(_Stroke.fromJson)
            .where((s) => _strokeToolIsPersistedInk(s.tool)),
      );
  }

  void pushStrokeListSnapshotUndo(_StrokeListSnapshotUndo beforeGesture) {
    unifiedUndo.add(beforeGesture);
    redoStack.clear();
    _trimUnifiedUndo();
  }

  /// Pixel eraser: split ink into independent strokes; does not store eraser paths.
  void applyPixelEraserPolyline(List<Offset> path, double radius, Uuid uuid) {
    if (path.isEmpty) return;
    var pl = path;
    if (pl.length == 1) {
      pl = [pl.first, pl.first + const Offset(0.55, 0.55)];
    }
    if (pl.length < 2) return;
    unifiedUndo.add(_StrokeListSnapshotUndo.fromStrokes(strokes));
    redoStack.clear();
    final eraserBounds = _eraserPolylineBounds(pl).inflate(radius + 80.0);
    final next = <_Stroke>[];
    for (final s in strokes) {
      if (!_strokeToolIsPersistedInk(s.tool)) continue;
      final threshold = radius + (s.width * 0.5) + 12.0;
      final strokeBounds = _MaterialsPageState._strokePixelBounds(
        s,
      ).inflate(threshold);
      if (!strokeBounds.overlaps(eraserBounds)) {
        next.add(s);
        continue;
      }
      next.addAll(_splitStrokeForPixelEraser(s, pl, radius, uuid));
    }
    strokes
      ..clear()
      ..addAll(next);
    _trimUnifiedUndo();
  }

  bool _strokeIntersectsPath(
    _Stroke stroke,
    List<Offset> eraserPoints,
    double radius,
  ) {
    final threshold = radius + (stroke.width * 0.5);
    if (stroke.points.isEmpty || eraserPoints.isEmpty) return false;

    // Point/segment checks for taps or very short paths.
    if (eraserPoints.length == 1) {
      final p = eraserPoints.first;
      for (var i = 0; i < stroke.points.length - 1; i++) {
        if (_distancePointToSegment(
              p,
              stroke.points[i],
              stroke.points[i + 1],
            ) <=
            threshold) {
          return true;
        }
      }
      return false;
    }

    // Segment/segment checks: robust for quick strokes and sparse sample points.
    for (var ei = 0; ei < eraserPoints.length - 1; ei++) {
      final ea = eraserPoints[ei];
      final eb = eraserPoints[ei + 1];
      for (var si = 0; si < stroke.points.length - 1; si++) {
        final sa = stroke.points[si];
        final sb = stroke.points[si + 1];
        if (_distanceSegmentToSegment(ea, eb, sa, sb) <= threshold) {
          return true;
        }
      }
    }
    return false;
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return (p - a).distance;
    final t =
        (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) / (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + dx * clamped, a.dy + dy * clamped);
    return (p - proj).distance;
  }

  double _distanceSegmentToSegment(Offset a, Offset b, Offset c, Offset d) {
    return math.min(
      math.min(
        _distancePointToSegment(a, c, d),
        _distancePointToSegment(b, c, d),
      ),
      math.min(
        _distancePointToSegment(c, a, b),
        _distancePointToSegment(d, a, b),
      ),
    );
  }

  /// Undo last stroke or lasso layout change (whichever was most recent).
  void undoLast() {
    if (unifiedUndo.isEmpty) return;
    final last = unifiedUndo.removeLast();
    if (last is _PageVisualStateSnapshot) {
      redoStack.add(_PageVisualStateSnapshot.fromPage(this));
      last.applyTo(this);
      return;
    }
    if (last is _LassoLayoutSnapshot) {
      redoStack.add(_captureLayoutRedoMirror(this, last));
      _applyLassoLayoutSnapshot(this, last);
      return;
    }
    if (last is _StrokeListSnapshotUndo) {
      redoStack.add(
        _StrokeListRedoEntry(
          afterJson: strokes.map((s) => s.toJson()).toList(),
        ),
      );
      strokes
        ..clear()
        ..addAll(
          last.strokesJson
              .map(_Stroke.fromJson)
              .where((s) => _strokeToolIsPersistedInk(s.tool)),
        );
      return;
    }
    if (last is _StrokeUndoMarker) {
      if (strokes.isNotEmpty) {
        redoStack.add(strokes.removeLast());
      }
      return;
    }
  }

  void redo() {
    if (redoStack.isEmpty) return;
    final item = redoStack.removeLast();
    if (item is _PageVisualStateSnapshot) {
      unifiedUndo.add(_PageVisualStateSnapshot.fromPage(this));
      item.applyTo(this);
      _trimUnifiedUndo();
      return;
    }
    if (item is _LassoLayoutSnapshot) {
      unifiedUndo.add(_captureLayoutRedoMirror(this, item));
      _applyLassoLayoutSnapshot(this, item);
      _trimUnifiedUndo();
      return;
    }
    if (item is _StrokeListRedoEntry) {
      unifiedUndo.add(_StrokeListSnapshotUndo.fromStrokes(strokes));
      strokes
        ..clear()
        ..addAll(
          item.afterJson
              .map(_Stroke.fromJson)
              .where((s) => _strokeToolIsPersistedInk(s.tool)),
        );
      _trimUnifiedUndo();
      return;
    }
    if (item is _Stroke) {
      if (_strokeToolIsPersistedInk(item.tool)) {
        strokes.add(item);
        unifiedUndo.add(_StrokeUndoMarker());
      }
      _trimUnifiedUndo();
      return;
    }
  }

  void clear() {
    strokes.clear();
    redoStack.clear();
    unifiedUndo.clear();
  }

  Rect _eraserPolylineBounds(List<Offset> pts) {
    var minX = pts.first.dx;
    var minY = pts.first.dy;
    var maxX = pts.first.dx;
    var maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.index,
    'sourcePdfId': sourcePdfId,
    'sourcePdfPageIndex': sourcePdfPageIndex,
    'sourceImagePath': sourceImagePath,
    'canvasRotationQuarterTurns': canvasRotationQuarterTurns,
    'strokes': strokes
        .where((s) => _strokeToolIsPersistedInk(s.tool))
        .map((s) => s.toJson())
        .toList(),
    'redoStack': redoStack.map((Object o) {
      if (o is _StrokeListRedoEntry) return o.toJson();
      if (o is _Stroke) return o.toJson();
      return <String, dynamic>{};
    }).toList(),
    'placedImages': placedImages.map((e) => e.toJson()).toList(),
    'textBoxes': textBoxes.map((e) => e.toJson(emitPageId: id)).toList(),
  };

  factory _CanvasPage.fromJson(
    Map<String, dynamic> json, {
    String? legacyMemoPdfId,
    int memoLegacyCanvasRotation = 0,
  }) {
    final strokesJson = json['strokes'] as List<dynamic>? ?? const [];
    final redoJson = json['redoStack'] as List<dynamic>? ?? const [];
    final imgJson = json['placedImages'] as List<dynamic>? ?? const [];
    final textJson = json['textBoxes'] as List<dynamic>? ?? const [];

    final kindIdx = json['kind'] as int?;
    late final _CanvasPageKind kind;
    String? pdfId;
    int? pdfIdx;
    String? imgPath;

    if (kindIdx != null) {
      kind = _CanvasPageKind
          .values[kindIdx.clamp(0, _CanvasPageKind.values.length - 1)];
      pdfId = json['sourcePdfId']?.toString();
      pdfIdx = (json['sourcePdfPageIndex'] as num?)?.toInt();
      imgPath = json['sourceImagePath']?.toString();
    } else {
      // Legacy v3: pages did not carry an explicit kind.
      if (legacyMemoPdfId != null) {
        kind = _CanvasPageKind.pdf;
        pdfId = legacyMemoPdfId;
        pdfIdx = (json['pdfPage'] as num?)?.toInt() ?? 0;
      } else {
        kind = _CanvasPageKind.memo;
      }
    }

    final int canvasRotationQuarterTurns;
    if (json.containsKey('canvasRotationQuarterTurns')) {
      canvasRotationQuarterTurns =
          (json['canvasRotationQuarterTurns'] as num?)?.toInt().clamp(0, 3) ??
          0;
    } else {
      canvasRotationQuarterTurns = memoLegacyCanvasRotation.clamp(0, 3);
    }

    return _CanvasPage(
      id: json['id'] as String? ?? Uuid().v4(),
      kind: kind,
      sourcePdfId: pdfId,
      sourcePdfPageIndex: pdfIdx,
      sourceImagePath: imgPath,
      canvasRotationQuarterTurns: canvasRotationQuarterTurns,
      strokes: strokesJson
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_Stroke.fromJson)
          .where((s) => _strokeToolIsPersistedInk(s.tool))
          .toList(),
      redoStack: _parseRedoStack(redoJson),
      placedImages: imgJson
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_PlacedImage.fromJson)
          .toList(),
      textBoxes: textJson
          .whereType<Map>()
          .map(
            (m) => _CanvasTextBox.fromJson(
              Map<String, dynamic>.from(m),
              pageId: json['id']?.toString(),
            ),
          )
          .toList(),
    );
  }
}

class _Stroke {
  final String id;
  final List<Offset> points;
  final _ToolType tool;
  final Color color;
  final double width;

  _Stroke({
    required this.id,
    required this.points,
    required this.tool,
    required this.color,
    required this.width,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'tool': tool.index,
    'color': color.toARGB32(),
    'width': width,
  };

  factory _Stroke.fromJson(Map<String, dynamic> json) {
    final pointsJson = json['points'] as List<dynamic>? ?? const [];
    final parsedPoints = <Offset>[];
    for (final p in pointsJson) {
      if (p is List && p.length == 2) {
        final dx = (p[0] as num?)?.toDouble();
        final dy = (p[1] as num?)?.toDouble();
        if (dx != null && dy != null) parsedPoints.add(Offset(dx, dy));
      }
    }
    final toolIndex = _mpInt(json, 'tool', _ToolType.pen.index);
    return _Stroke(
      id: _mpString(json, 'id', Uuid().v4()),
      points: parsedPoints
          .where((p) => p.dx.isFinite && p.dy.isFinite)
          .toList(),
      tool: _ToolType.values[toolIndex.clamp(0, _ToolType.values.length - 1)],
      color: _mpColor(json['color'], _memoDefaultInkColor),
      width: _mpDouble(json, 'width', 4.0).clamp(0.1, 128.0),
    );
  }
}

List<Object> _parseRedoStack(List<dynamic> json) {
  final out = <Object>[];
  for (final e in json) {
    if (e is! Map) continue;
    final map = Map<String, dynamic>.from(e);
    if (map['kind'] == 'strokeListRedo') {
      out.add(_StrokeListRedoEntry.fromJson(map));
    } else {
      final s = _Stroke.fromJson(map);
      if (_strokeToolIsPersistedInk(s.tool)) {
        out.add(s);
      }
    }
  }
  return out;
}

double _pixelEraserDistPointToSegment(Offset p, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx == 0 && dy == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * dx) + ((p.dy - a.dy) * dy)) / (dx * dx + dy * dy);
  final clamped = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + dx * clamped, a.dy + dy * clamped);
  return (p - proj).distance;
}

double _pixelEraserMinDistToPolyline(Offset p, List<Offset> poly) {
  if (poly.isEmpty) return double.infinity;
  if (poly.length == 1) return (p - poly.first).distance;
  var best = double.infinity;
  for (var i = 0; i < poly.length - 1; i++) {
    best = math.min(
      best,
      _pixelEraserDistPointToSegment(p, poly[i], poly[i + 1]),
    );
  }
  return best;
}

/// Samples each segment and splits where the eraser tube hits ink.
List<_Stroke> _splitStrokeForPixelEraser(
  _Stroke stroke,
  List<Offset> eraser,
  double radius,
  Uuid uuid,
) {
  if (!_strokeToolIsPersistedInk(stroke.tool)) return const [];
  final pts = stroke.points;
  if (pts.length < 2) return [stroke];
  const sub = 14;
  final samples = <Offset>[];
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i];
    final b = pts[i + 1];
    for (var k = 0; k <= sub; k++) {
      if (i > 0 && k == 0) continue;
      final t = k / sub;
      samples.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
    }
  }
  final out = <_Stroke>[];
  var run = <Offset>[];
  void flush() {
    if (run.length >= 2) {
      out.add(
        _Stroke(
          id: uuid.v4(),
          points: List<Offset>.from(run),
          tool: stroke.tool,
          color: stroke.color,
          width: stroke.width,
        ),
      );
    }
    run = [];
  }

  for (final p in samples) {
    if (_pixelEraserMinDistToPolyline(p, eraser) <= radius) {
      flush();
    } else {
      run.add(p);
    }
  }
  flush();
  return out;
}
