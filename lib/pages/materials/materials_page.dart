import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';

import '../../core/responsive.dart';
import '../../services/local_storage_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/adaptive_scaffold.dart';

part 'materials_page_models.dart';
part 'materials_page_canvas_data.dart';
part 'materials_page_painters.dart';
part 'materials_page_side_top.dart';
part 'materials_page_pdf_background.dart';
part 'materials_page_tool_dock.dart';
part 'materials_page_advanced_color_dialog.dart';
part 'materials_page_dialogs.dart';
part 'materials_page_text_object.dart';

/// Matches auto-generated memo titles like `메모 1` / `메모1` (same folder only).
final RegExp _memoAutoTitleNumber = RegExp(r'^메모\s*(\d+)\s*$');

/// pdfx native side is registered at engine startup (iOS [GeneratedPluginRegistrant]).
Future<void> _ensurePdfxRegistration() => Future.value();

int _memoNavigatorPdfPageIndex(_PdfAsset asset, _CanvasPage page) {
  final n = asset.pageCount ?? 1;
  if (n < 1) return 0;
  return (page.sourcePdfPageIndex ?? 0).clamp(0, n - 1);
}

_PdfAsset? _memoNavigatorPdfAsset(List<_PdfAsset> pdfs, _CanvasPage page) {
  if (page.kind != _CanvasPageKind.pdf || page.sourcePdfId == null) {
    return null;
  }
  for (final p in pdfs) {
    if (p.id == page.sourcePdfId) return p;
  }
  return null;
}

/// Smallest positive integer not used by an auto-style memo title in [folderId].
int _nextMemoAutoTitleNumber(List<_Memo> memos, String folderId) {
  final used = <int>{};
  for (final m in memos) {
    if (m.folderId != folderId) continue;
    final match = _memoAutoTitleNumber.firstMatch(m.name.trim());
    if (match == null) continue;
    final v = int.tryParse(match.group(1)!);
    if (v != null && v > 0) used.add(v);
  }
  var n = 1;
  while (used.contains(n)) {
    n++;
  }
  return n;
}

/// Materials memo laser pipeline — `grep LASER_DIAG` while reproducing.
const bool _kLaserDiagEnabled = false;

void _laserDiag(String message) {
  if (!kDebugMode || !_kLaserDiagEnabled) return;
  debugPrint('[LASER_DIAG] $message');
}

/// Which part of a text box the color palette edits while the text tool is active.
enum _TextStyleColorTarget { text, fill, border }

/// Shared line-height factor for canvas TextField ↔ TextPainter ↔ layout.
const double _kCanvasTextLineHeight = 1.28;

// Selection overlay metrics (lasso painter + hit tests; keep in sync).
const double _studioSelFabSize = 30;
const double _studioSelFabGap = 4;
const double _studioSelBarPad = 6;
const double _studioSelHandle = 5;
const double _studioSelRotateGap = 8;
const double _studioSelRotateR = 12;

Offset _studioRotateKnobCenter(Rect bounds) => Offset(
  bounds.center.dx,
  bounds.top - _studioSelRotateGap - _studioSelRotateR,
);

Rect _studioSelectionCopyFabRect(Rect bounds) {
  final total = _studioSelFabSize * 2 + _studioSelFabGap;
  final left = bounds.center.dx - total * 0.5;
  final top = bounds.bottom + _studioSelBarPad;
  return Rect.fromLTWH(left, top, _studioSelFabSize, _studioSelFabSize);
}

Rect _studioSelectionDeleteFabRect(Rect bounds) {
  final c = _studioSelectionCopyFabRect(bounds);
  return Rect.fromLTWH(
    c.right + _studioSelFabGap,
    c.top,
    _studioSelFabSize,
    _studioSelFabSize,
  );
}

// ── Lasso polygon geometry (freehand selection) ─────────────────

bool _pointInPolygon(Offset p, List<Offset> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final pi = poly[i];
    final pj = poly[j];
    final intersect =
        ((pi.dy > p.dy) != (pj.dy > p.dy)) &&
        (p.dx <
            (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy + 1e-10) + pi.dx);
    if (intersect) inside = !inside;
  }
  return inside;
}

double _cross2(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

bool _segmentsIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
  final d1 = _cross2(p4 - p3, p1 - p3);
  final d2 = _cross2(p4 - p3, p2 - p3);
  final d3 = _cross2(p2 - p1, p3 - p1);
  final d4 = _cross2(p2 - p1, p4 - p1);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  const eps = 1e-9;
  if (d1.abs() < eps && _onSegment(p3, p4, p1)) return true;
  if (d2.abs() < eps && _onSegment(p3, p4, p2)) return true;
  if (d3.abs() < eps && _onSegment(p1, p2, p3)) return true;
  if (d4.abs() < eps && _onSegment(p1, p2, p4)) return true;
  return false;
}

bool _onSegment(Offset a, Offset b, Offset p) {
  return p.dx <= math.max(a.dx, b.dx) + 1e-9 &&
      p.dx + 1e-9 >= math.min(a.dx, b.dx) &&
      p.dy <= math.max(a.dy, b.dy) + 1e-9 &&
      p.dy + 1e-9 >= math.min(a.dy, b.dy);
}

Rect _polygonBounds(List<Offset> poly) {
  var minX = poly.first.dx;
  var minY = poly.first.dy;
  var maxX = poly.first.dx;
  var maxY = poly.first.dy;
  for (final p in poly) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

bool _rotatedRectContainsPoint(Rect r, double rotationRad, Offset point) {
  if (rotationRad.abs() < 1e-6) return r.contains(point);
  final local = _rotateDocVector(point - r.center, -rotationRad) + r.center;
  return r.contains(local);
}

bool _polygonIntersectsRotatedRect(
  List<Offset> poly,
  Rect r,
  double rotationRad,
) {
  if (poly.length < 3) return false;
  final corners = <Offset>[];
  final c = r.center;
  final hx = r.width * 0.5;
  final hy = r.height * 0.5;
  const signs = <(double, double)>[(-1, -1), (1, -1), (1, 1), (-1, 1)];
  for (final sg in signs) {
    final local = Offset(sg.$1 * hx, sg.$2 * hy);
    corners.add(c + _rotateDocVector(local, rotationRad));
  }
  var minX = corners.first.dx;
  var maxX = corners.first.dx;
  var minY = corners.first.dy;
  var maxY = corners.first.dy;
  for (final corner in corners) {
    minX = math.min(minX, corner.dx);
    maxX = math.max(maxX, corner.dx);
    minY = math.min(minY, corner.dy);
    maxY = math.max(maxY, corner.dy);
  }
  final rectBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  if (!_polygonBounds(poly).overlaps(rectBounds)) return false;
  if (_pointInPolygon(c, poly)) return true;
  for (final p in poly) {
    if (_rotatedRectContainsPoint(r, rotationRad, p)) return true;
  }
  for (final corner in corners) {
    if (_pointInPolygon(corner, poly)) return true;
  }
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    for (var j = 0; j < corners.length; j++) {
      final c0 = corners[j];
      final c1 = corners[(j + 1) % corners.length];
      if (_segmentsIntersect(a, b, c0, c1)) return true;
    }
  }
  return false;
}

double _distToSegmentForLasso(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;
  final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (ab2 < 1e-6) return (p - a).distance;
  var t = (ap.dx * ab.dx + ap.dy * ab.dy) / ab2;
  t = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - proj).distance;
}

double _minDistanceToPolygonBoundary(Offset p, List<Offset> poly) {
  if (poly.length < 2) return double.infinity;
  var best = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    best = math.min(best, _distToSegmentForLasso(p, a, b));
  }
  return best;
}

bool _strokeTouchedByPolygon(_Stroke s, List<Offset> poly) {
  if (poly.length < 3 || s.points.isEmpty) return false;
  if (!_strokeToolIsPersistedInk(s.tool)) return false;
  final b = _MaterialsPageState._strokePixelBounds(s);
  if (!_polygonBounds(poly).overlaps(b)) return false;
  if (_pointInPolygon(b.center, poly)) return true;
  for (final p in s.points) {
    if (_pointInPolygon(p, poly)) return true;
  }
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b0 = poly[(i + 1) % poly.length];
    for (var j = 0; j < s.points.length - 1; j++) {
      if (_segmentsIntersect(a, b0, s.points[j], s.points[j + 1])) {
        return true;
      }
    }
  }
  // Near-miss: strokes that graze the lasso path are easy to miss with
  // strict inside / segment tests; allow a small margin by stroke width.
  final margin = math.max(12.0, s.width * 0.5 + 8.0);
  for (final p in s.points) {
    if (_minDistanceToPolygonBoundary(p, poly) <= margin) return true;
  }
  return false;
}

List<Offset> _lassoRibbonAlongSegment(
  Offset a,
  Offset b, {
  double halfWidth = 7,
}) {
  final d = (b - a).distance;
  if (d < 0.01) {
    return [
      a + Offset(-halfWidth, -halfWidth),
      a + Offset(halfWidth, -halfWidth),
      a + Offset(halfWidth, halfWidth),
      a + Offset(-halfWidth, halfWidth),
    ];
  }
  final u = Offset((b.dx - a.dx) / d, (b.dy - a.dy) / d);
  final n = Offset(-u.dy * halfWidth, u.dx * halfWidth);
  return [a + n, b + n, b - n, a - n];
}

List<Offset> _prepareLassoSelectionPath(List<Offset> path) {
  if (path.length >= 3) return path;
  if (path.length == 2) {
    return _lassoRibbonAlongSegment(path[0], path[1]);
  }
  return path;
}

Offset _rotateDocVector(Offset v, double radians) {
  final c = math.cos(radians);
  final s = math.sin(radians);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

double _unwrapAngleDelta(double d) {
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}

// ── PAGE WIDGET ──────────────────────────────────────────────────

class MaterialsPage extends StatefulWidget {
  const MaterialsPage({super.key});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

enum _ToolDockPanelKind { color, width }

/// In-memory clipboard for canvas objects (lasso copy / long-press paste).
class _StudioClipboardPayload {
  _StudioClipboardPayload({
    required this.anchorDoc,
    required this.strokeMaps,
    required this.textMaps,
    required this.imageMaps,
  });

  final Offset anchorDoc;
  final List<Map<String, dynamic>> strokeMaps;
  final List<Map<String, dynamic>> textMaps;
  final List<Map<String, dynamic>> imageMaps;
}

class _MaterialsPageState extends State<MaterialsPage> {
  static const _sessionKey = 'materials_studio_session_v2';
  static const _uuid = Uuid();
  static const double _studioPanelExpandedWidth = 226;
  static const double _studioPanelCollapsedWidth = 42;

  final TransformationController _transformController =
      TransformationController();
  final LocalStorageService _storage = const LocalStorageService();

  List<_Folder> _folders = [];
  List<_Memo> _memos = [];
  List<_PdfAsset> _uploadedPdfs = const [];

  String? _activeFolderId;
  String? _activeMemoId;
  int _activePage = 0;

  _ToolType _tool = _ToolType.pen;
  _ToolType? _dockTool;
  _ToolDockPanelKind? _dockPanelKind;

  /// When true, the text formatting strip under the dock stays hidden until
  /// the user taps Aa again (only while no text is being edited/selected).
  bool _textAuxiliaryBarHidden = false;

  /// While the color dock is open for text **fill**, live alpha (0–1) for the slider.
  double? _colorPanelFillAlpha;
  _PaperStyle _paperStyle = _PaperStyle.ruled;
  _EraserMode _eraserMode = _EraserMode.pixel;
  late final Map<_ToolType, _ToolSettings> _toolSettings = {
    _ToolType.pen: _ToolSettings(
      color: _memoDefaultInkColor,
      width: 4.0,
      opacity: 1,
    ),
    _ToolType.pencil: _ToolSettings(
      color: _memoDefaultInkColor,
      width: 3.2,
      opacity: 0.8,
    ),
    _ToolType.highlighter: _ToolSettings(
      color: const Color(0xFFF59E0B),
      width: 6.0,
      opacity: 0.28,
    ),
    _ToolType.eraser: _ToolSettings(
      color: Colors.transparent,
      width: 8.0,
      opacity: 1,
    ),
    _ToolType.text: _ToolSettings(
      color: _memoDefaultInkColor,
      width: 18,
      opacity: 1,
      bold: false,
      italic: false,
      textFontFamily: 'Pretendard',
      textUnderline: false,
      textAlignIndex: 0,
    ),
    _ToolType.laser: _ToolSettings(
      color: const Color(0xFFFF3355),
      width: 5.0,
      opacity: 1.0,
      laserModeIndex: 1,
      laserDismissMs: 800,
    ),
  };
  List<Color> _recentColors = const [
    _memoDefaultInkColor,
    Color(0xFF2563EB),
    Color(0xFFF59E0B),
    Color(0xFFE11D48),
    Color(0xFF34D399),
  ];
  bool _stylusOnly = true;
  bool _isStudioPanelCollapsed = false;

  List<Offset>? _workingPoints;

  /// Stroke-eraser gesture: before snapshot; one undo entry on pointer-up if changed.
  _StrokeListSnapshotUndo? _pendingStrokeEraserUndo;
  int _lastStrokeEraserAnnotMs = 0;
  int? _activePointer;
  final Map<int, Offset> _touchPoints = {};
  bool _isPageSwipeActive = false;
  Offset? _pageSwipeStart;
  Offset? _pageSwipeCurrent;
  double? _pageSwipeStartFingerDist;
  // Snapshot of the transform/anchors at the moment the 2-finger gesture began.
  // Used to apply pinch+pan manually so the lock check is enforced synchronously
  // (InteractiveViewer's scale recognizer would otherwise claim pointers in the
  // narrow window between an edit pointer arriving and the next rebuild).
  Matrix4? _twoFingerStartMatrix;
  Offset? _twoFingerStartCenter;
  DateTime? _lastPageFlipAt;
  bool _isRestoring = true;
  bool _enforceStylusOnly = true;
  Timer? _saveDebounce;
  _TextStyleColorTarget _textStyleColorTarget = _TextStyleColorTarget.text;
  bool _pdfStripExpanded = false;

  /// Repaints only the memo annotation stack (strokes / preview) without
  /// rebuilding the whole studio panel.
  final ValueNotifier<int> _annotationRepaint = ValueNotifier<int>(0);

  /// Debug overlay refresh (touch vs document); only bumped in debug builds.
  final ValueNotifier<int> _debugPointerRepaint = ValueNotifier<int>(0);

  Offset? _debugTouchDoc;
  Offset? _debugAppliedDoc;

  /// Ephemeral laser overlay (not persisted).
  final ValueNotifier<int> _laserRepaint = ValueNotifier<int>(0);
  final List<Offset> _laserTrail = [];
  Offset? _laserDotDoc;
  double _laserTrailOpacity = 1.0;
  Timer? _laserClearTimer;
  Timer? _laserFadeTimer;
  Timer? _laserDotHideTimer;

  /// Repaints only the memo text object layer.
  final ValueNotifier<int> _textLayerRepaint = ValueNotifier<int>(0);

  /// Layout bounds of the memo page board (for page-jump dialog alignment).
  /// Memo editing chrome (outside [InteractiveViewer]) — stable viewport for
  /// overlays such as the page navigator (not affected by canvas zoom/pan).
  final GlobalKey _memoEditViewportKey = GlobalKey();

  /// Live document-space canvas size (the inside of the A4 AspectRatio in the
  /// editor). Captured during layout so previews and other off-canvas surfaces
  /// can render strokes/text/images in the same coordinate frame they were
  /// drawn in. Falls back to a sensible A4 default until the first layout.
  Size _liveCanvasSize = const Size(360, 360 * 1.414);

  bool _lassoFilterText = true;
  bool _lassoFilterDrawing = true;
  bool _lassoFilterImage = true;

  final Set<String> _selectedStrokeIds = {};
  final Set<String> _selectedImageIds = {};
  final Set<String> _selectedTextIds = {};

  int? _lassoPointerId;
  _LassoDragKind _lassoDrag = _LassoDragKind.idle;
  List<Offset>? _lassoPathLocal;
  Offset? _lassoGestureStartLocal;
  int _lassoResizeCorner = 0;
  Offset? _lassoMoveAnchorLocal;

  Map<String, List<Offset>>? _lassoMoveStrokePointsStart;
  Map<String, _NormRect>? _lassoMoveImageNormStart;
  Map<String, _NormRect>? _lassoMoveTextNormStart;

  /// Pending marquee state: a one-finger touch that *might* turn into a
  /// new selection drag. We defer the actual clear/marquee start until the
  /// finger moves past a threshold so two-finger zoom/pan can preempt it
  /// without losing the current lasso selection.
  int? _lassoPendingMarqueePointer;
  Offset? _lassoPendingMarqueeStart;
  static const double _kLassoMarqueeStartSlop = 5.0;

  /// Oriented bounding box (OBB) of the current lasso selection.
  ///
  /// `_selBaseBounds` is the AABB at the moment selection geometry was last
  /// committed (after lasso polygon, move, or resize). During rotation, only
  /// `_selRotationRad` changes — the painter rotates the rectangle around
  /// `_selBaseBounds.center` so the visible chrome tilts with its contents.
  Rect? _selBaseBounds;
  double _selRotationRad = 0;

  /// Snapshots captured when the resize gesture starts so undo/redo and
  /// mid-drag math see consistent baseline geometry for every selected child.
  Map<String, List<Offset>>? _lassoResizeStrokePointsStart;
  Map<String, _NormRect>? _lassoResizeImageNormStart;
  Map<String, _NormRect>? _lassoResizeTextNormStart;
  Map<String, double>? _lassoResizeTextFontStart;
  Rect? _lassoResizeStartAabb; // _selBaseBounds at the start of resize.

  /// Snapshots captured when the rotation gesture starts so each text/image
  /// can be rigidly rotated around the lasso pivot (in addition to its own
  /// `rotationDeg`).
  Map<String, Offset>? _lassoRotateTextCenterStart;
  Map<String, Offset>? _lassoRotateImageCenterStart;

  /// Norm rects at rotate gesture start (stable width/height while pivoting).
  Map<String, _NormRect>? _lassoRotateTextNormRectStart;
  Map<String, _NormRect>? _lassoRotateImageNormRectStart;

  Size? _pointerCanvasSize;

  bool _lassoMoveDidChange = false;
  bool _lassoResizeDidChange = false;
  bool _lassoRotateDidChange = false;
  _LassoLayoutSnapshot? _pendingMoveUndo;
  _LassoLayoutSnapshot? _pendingResizeUndo;
  _LassoLayoutSnapshot? _pendingRotateUndo;
  Offset? _lassoRotatePivot;
  double? _lassoRotatePointerStartAngle;
  double _lassoRotateBoxStartRad = 0;
  Map<String, List<Offset>>? _lassoRotateStrokeBaseline;
  Map<String, double>? _lassoRotateTextStartDeg;
  Map<String, double>? _lassoRotateImageStartDeg;

  _StudioClipboardPayload? _studioClipboard;

  Timer? _canvasLongPressTimer;
  int? _longPressPointerId;
  Offset? _longPressOriginDoc;
  Offset? _longPressOriginGlobal;

  String? _textEditingId;
  TextEditingController? _textEditController;

  /// Snapshot of all text boxes when inline edit began (one undo step on commit).
  List<Map<String, dynamic>>? _inlineTextEditUndoBaseline;
  final FocusNode _textFieldFocus = FocusNode();
  Offset? _textToolPointerDownLocal;
  int? _textToolActivePointer;

  _LassoLayoutSnapshot? _pendingCanvasTextDragUndo;
  String? _pendingCanvasTextDragId;
  bool _canvasTextDragDidChange = false;

  _LassoLayoutSnapshot? _pendingCanvasTextResizeUndo;
  String? _pendingCanvasTextResizeId;
  bool _canvasTextResizeChanged = false;

  _LassoLayoutSnapshot? _pendingCanvasTextRotateUndo;
  String? _pendingCanvasTextRotateId;
  bool _canvasTextRotateChanged = false;

  // ── Getters ──────────────────────────────────────────────────

  _Memo? get _activeMemo {
    if (_activeMemoId == null) return null;
    try {
      return _memos.firstWhere((m) => m.id == _activeMemoId);
    } catch (_) {
      return null;
    }
  }

  int get _safeActivePage {
    final memo = _activeMemo;
    if (memo == null || memo.pages.isEmpty) return 0;
    return _activePage.clamp(0, memo.pages.length - 1);
  }

  _CanvasPage? get _activeMemoPage {
    final memo = _activeMemo;
    if (memo == null || memo.pages.isEmpty) return null;
    return memo.pages[_safeActivePage];
  }

  _PdfAsset? _pdfAssetForCanvasPage(_CanvasPage page) {
    if (page.kind != _CanvasPageKind.pdf) return null;
    final id = page.sourcePdfId;
    if (id == null) return null;
    try {
      return _uploadedPdfs.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  int _pdfRenderPageIndexFor(_PdfAsset asset, _CanvasPage page) {
    final n = asset.pageCount ?? 1;
    if (n < 1) return 0;
    return (page.sourcePdfPageIndex ?? 0).clamp(0, n - 1);
  }

  bool _memoReferencesPdfAsset(_Memo memo, String pdfId) {
    if (memo.pdfId == pdfId) return true;
    for (final p in memo.pages) {
      if (p.kind == _CanvasPageKind.pdf && p.sourcePdfId == pdfId) {
        return true;
      }
    }
    return false;
  }

  void _repointMemoPrimaryPdfAfterRemoval(_Memo memo, String removedPdfId) {
    if (memo.pdfId != removedPdfId) return;
    for (final p in memo.pages) {
      if (p.kind == _CanvasPageKind.pdf && p.sourcePdfId != null) {
        memo.pdfId = p.sourcePdfId;
        return;
      }
    }
    memo.pdfId = null;
  }

  _ToolSettings _defaultToolSettings(_ToolType tool) {
    switch (tool) {
      case _ToolType.pen:
        return _ToolSettings(
          color: _memoDefaultInkColor,
          width: 4.0,
          opacity: 1,
        );
      case _ToolType.pencil:
        return _ToolSettings(
          color: _memoDefaultInkColor,
          width: 3.2,
          opacity: 0.8,
        );
      case _ToolType.highlighter:
        return _ToolSettings(
          color: const Color(0xFFF59E0B),
          width: 6.0,
          opacity: 0.28,
        );
      case _ToolType.eraser:
        return _ToolSettings(color: Colors.transparent, width: 8.0, opacity: 1);
      case _ToolType.hand:
        return _ToolSettings(
          color: _memoDefaultInkColor,
          width: 4.0,
          opacity: 1,
        );
      case _ToolType.lasso:
        return _ToolSettings(
          color: _memoDefaultInkColor,
          width: 4.0,
          opacity: 1,
        );
      case _ToolType.text:
        return _ToolSettings(
          color: _memoDefaultInkColor,
          width: 18,
          opacity: 1,
          bold: false,
          italic: false,
          textFontFamily: 'Pretendard',
          textUnderline: false,
          textAlignIndex: 0,
        );
      case _ToolType.laser:
        return _ToolSettings(
          color: const Color(0xFFFF3355),
          width: 5.0,
          opacity: 1.0,
          laserModeIndex: 1,
          laserDismissMs: 800,
        );
    }
  }

  _ToolSettings _settingsFor(_ToolType tool) {
    return _toolSettings.putIfAbsent(tool, () => _defaultToolSettings(tool));
  }

  _ToolSettings get _activeToolSettings => _settingsFor(_tool);

  Color get _activeColor => _activeToolSettings.color;

  double get _activeWidth => _activeToolSettings.width;

  double get _activeOpacity => _activeToolSettings.opacity;

  /// When false, the text object stack is wrapped in [IgnorePointer] so drawing tools
  /// and lasso reach the canvas [Listener]. Lasso selects text via geometry, not these widgets.
  bool get _textCanvasLayerAbsorbsPointers => _tool == _ToolType.text;

  bool get _showTextAuxiliaryBar {
    if (_activeMemoPage == null) return false;
    final wantsChrome =
        _tool == _ToolType.text ||
        _textEditingId != null ||
        _selectedTextIds.isNotEmpty;
    if (!wantsChrome) return false;
    if (_textAuxiliaryBarHidden &&
        _tool == _ToolType.text &&
        _textEditingId == null &&
        _selectedTextIds.isEmpty) {
      return false;
    }
    return true;
  }

  bool get _isDockOpen =>
      _dockTool == _tool &&
      _dockPanelKind != null &&
      (_tool != _ToolType.lasso || _selectedTextIds.isNotEmpty);

  Color get _toolbarColorPreview {
    if (_tool == _ToolType.text) {
      final tgt = _primaryTextToolbarTarget();
      final ts = _settingsFor(_ToolType.text);
      switch (_textStyleColorTarget) {
        case _TextStyleColorTarget.text:
          return tgt?.color ?? ts.color;
        case _TextStyleColorTarget.fill:
          return tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor;
        case _TextStyleColorTarget.border:
          return tgt?.borderColor ?? ts.textBoxNextBorderColor;
      }
    }
    if (_tool == _ToolType.lasso && _selectedTextIds.isNotEmpty) {
      final page = _activeMemoPage;
      if (page != null) {
        for (final t in page.textBoxes) {
          if (_selectedTextIds.contains(t.id)) return t.color;
        }
      }
    }
    return _activeColor;
  }

  Color get _activeStrokeColor {
    if (_tool == _ToolType.eraser) return Colors.white;
    if (_tool == _ToolType.laser) {
      return _activeColor.withValues(alpha: 1.0);
    }
    return _activeColor.withValues(alpha: _activeOpacity);
  }

  double get _effectiveWidth {
    switch (_tool) {
      case _ToolType.laser:
        return _activeWidth.clamp(3.0, 8.0);
      case _ToolType.pencil:
        return (_activeWidth * 0.78).clamp(1.0, 10.0);
      case _ToolType.highlighter:
        return (_activeWidth * 1.9).clamp(3.0, 24.0);
      case _ToolType.eraser:
        if (_eraserMode == _EraserMode.pixel) {
          return (_activeWidth * 2.2).clamp(6.0, 38.0);
        }
        return 10.0;
      default:
        return _activeWidth;
    }
  }

  bool _isDrawingEnabled(PointerEvent event) {
    if (_tool == _ToolType.lasso ||
        _tool == _ToolType.text ||
        _tool == _ToolType.laser) {
      return true;
    }
    if (!_enforceStylusOnly) return true;
    if (!_stylusOnly) return true;
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  /// Laser trail/dot or pending fade/hide — treat as transient edit (block pinch).
  bool get _isLaserTransientActive =>
      _laserTrail.isNotEmpty ||
      _laserDotDoc != null ||
      _laserClearTimer != null ||
      _laserFadeTimer != null ||
      _laserDotHideTimer != null;

  /// True while any one-pointer (or laser transient) canvas edit could be in progress.
  /// Used to suppress [InteractiveViewer] pinch and two-finger canvas pan/page swipe.
  bool _isCanvasEditGestureLocked() {
    if (_activePointer != null) return true;
    if (_workingPoints != null) return true;
    if (_textToolActivePointer != null) return true;
    if (_textToolPointerDownLocal != null) return true;
    if (_lassoPointerId != null) return true;
    if (_lassoDrag != _LassoDragKind.idle) return true;
    if (_pendingCanvasTextDragId != null) return true;
    if (_pendingCanvasTextResizeId != null) return true;
    if (_pendingCanvasTextRotateId != null) return true;
    if (_textEditingId != null) return true;
    if (_isLaserTransientActive) return true;
    return false;
  }

  void _syncInteractiveViewerGestureAvailability() {
    if (!mounted) return;
    setState(() {});
  }

  /// Commits stroke-eraser undo (at most one) if the page changed since
  /// [_pendingStrokeEraserUndo] was captured.
  void _finalizeStrokeEraserUndoIfChanged() {
    final page = _activeMemoPage;
    final pending = _pendingStrokeEraserUndo;
    _pendingStrokeEraserUndo = null;
    if (page != null &&
        pending != null &&
        !_strokeUndoSnapshotMatchesPage(pending, page)) {
      page.pushStrokeListSnapshotUndo(pending);
      _markDirty();
    }
  }

  /// Ends an in-progress canvas [Listener] gesture (pen / eraser / laser) so
  /// tool switches and [dispose] never leave [_activePointer] stuck.
  void _abortCanvasListenerPointerGesture({
    bool commitStrokeEraserIfChanged = false,
  }) {
    if (_activePointer == null && _workingPoints == null) return;

    if (_tool == _ToolType.laser) {
      _activePointer = null;
      _workingPoints = null;
      _clearLaserOverlay();
      _notifyAnnotationLayer();
      _syncInteractiveViewerGestureAvailability();
      return;
    }

    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      if (commitStrokeEraserIfChanged) {
        _finalizeStrokeEraserUndoIfChanged();
      } else {
        final page = _activeMemoPage;
        final pending = _pendingStrokeEraserUndo;
        _pendingStrokeEraserUndo = null;
        if (page != null && pending != null) {
          page.replaceStrokesFromUndoSnapshot(pending);
        }
      }
      _workingPoints = null;
      _activePointer = null;
      _notifyAnnotationLayer();
      _syncInteractiveViewerGestureAvailability();
      return;
    }

    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.pixel) {
      _workingPoints = null;
      _activePointer = null;
      _pendingStrokeEraserUndo = null;
      _notifyAnnotationLayer();
      _syncInteractiveViewerGestureAvailability();
      return;
    }

    _workingPoints = null;
    _activePointer = null;
    _pendingStrokeEraserUndo = null;
    _notifyAnnotationLayer();
    _syncInteractiveViewerGestureAvailability();
  }

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _abortCanvasListenerPointerGesture(commitStrokeEraserIfChanged: true);
    _saveDebounce?.cancel();
    _textEditController?.dispose();
    _textFieldFocus.dispose();
    _transformController.dispose();
    _annotationRepaint.dispose();
    _debugPointerRepaint.dispose();
    _laserClearTimer?.cancel();
    _laserFadeTimer?.cancel();
    _laserDotHideTimer?.cancel();
    _laserRepaint.dispose();
    _textLayerRepaint.dispose();
    _canvasLongPressTimer?.cancel();
    super.dispose();
  }

  void _markDirty() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persistSession);
  }

  // ── Folder management ────────────────────────────────────────

  void _addFolder() {
    const folderColors = [
      Color(0xFF4DA3FF),
      Color(0xFFFF9F5A),
      Color(0xFF4FCB8D),
      Color(0xFF9B8CFF),
      Color(0xFFFF8FAB),
      Color(0xFF6FE7D8),
    ];
    final color = folderColors[_folders.length % folderColors.length];
    final folder = _Folder(
      id: _uuid.v4(),
      name: '폴더 ${_folders.length + 1}',
      color: color,
    );
    final memo = _Memo(
      id: _uuid.v4(),
      name: '메모 ${_nextMemoAutoTitleNumber(_memos, folder.id)}',
      folderId: folder.id,
    );
    setState(() {
      _folders = [..._folders, folder];
      _memos = [..._memos, memo];
      _activeFolderId = folder.id;
      _activeMemoId = memo.id;
      _activePage = 0;
    });
    _markDirty();
  }

  void _deleteFolder(String folderId) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('폴더 삭제'),
        content: Text('"${folder.name}" 폴더와 모든 메모를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final remaining = _memos.where((m) => m.folderId != folderId).toList();
    final remainingFolders = _folders.where((f) => f.id != folderId).toList();
    String? newFolderId;
    String? newMemoId;
    if (remainingFolders.isNotEmpty) {
      newFolderId = remainingFolders.first.id;
      final inFolder = remaining
          .where((m) => m.folderId == newFolderId)
          .toList();
      newMemoId = inFolder.isNotEmpty ? inFolder.first.id : null;
    }
    setState(() {
      _folders = remainingFolders;
      _memos = remaining;
      _activeFolderId = newFolderId;
      _activeMemoId = newMemoId;
      _activePage = 0;
    });
    _markDirty();
  }

  Future<void> _renameFolder(String folderId) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RenameDialog(title: '폴더 이름 변경', hint: '폴더 이름', initial: folder.name),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    setState(() => folder.name = newName);
    _markDirty();
  }

  // ── Memo management ──────────────────────────────────────────

  void _addMemo(String folderId) {
    final memo = _Memo(
      id: _uuid.v4(),
      name: '메모 ${_nextMemoAutoTitleNumber(_memos, folderId)}',
      folderId: folderId,
    );
    setState(() {
      _memos = [..._memos, memo];
      _activeFolderId = folderId;
      _activeMemoId = memo.id;
      _activePage = 0;
    });
    _markDirty();
  }

  void _deleteMemo(String memoId) async {
    final memo = _memos.firstWhere((m) => m.id == memoId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메모 삭제'),
        content: Text('"${memo.name}" 메모를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final remaining = _memos.where((m) => m.id != memoId).toList();
    String? newMemoId = _activeMemoId;
    String? newFolderId = _activeFolderId;
    if (_activeMemoId == memoId) {
      final inFolder = remaining
          .where((m) => m.folderId == memo.folderId)
          .toList();
      if (inFolder.isNotEmpty) {
        newMemoId = inFolder.first.id;
        newFolderId = memo.folderId;
      } else if (remaining.isNotEmpty) {
        newMemoId = remaining.first.id;
        newFolderId = remaining.first.folderId;
      } else {
        newMemoId = null;
        newFolderId = null;
      }
    }
    setState(() {
      _memos = remaining;
      _activeMemoId = newMemoId;
      _activeFolderId = newFolderId;
      _activePage = 0;
    });
    _markDirty();
  }

  Future<void> _renameMemo(String memoId) async {
    final memo = _memos.firstWhere((m) => m.id == memoId);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _RenameDialog(title: '메모 이름 변경', hint: '메모 이름', initial: memo.name),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    setState(() => memo.name = newName);
    _markDirty();
  }

  void _selectMemo(String memoId) {
    if (_activeMemoId == memoId) return;
    final memo = _memos.firstWhere((m) => m.id == memoId);
    setState(() {
      _activeMemoId = memoId;
      _activeFolderId = memo.folderId;
      _clearLaserOverlay();
      _activePage = 0;
      _clearSelection();
      _clearLassoInteraction();
    });
    _markDirty();
  }

  // ── Page management ──────────────────────────────────────────

  void _addPage() {
    final memo = _activeMemo;
    if (memo == null) return;
    setState(() {
      final insertAt = (_safeActivePage + 1).clamp(0, memo.pages.length);
      memo.pages.insert(insertAt, _CanvasPage.createDefaultMemoPage());
      _clearLaserOverlay();
      _activePage = insertAt;
      _clearSelection();
      _clearLassoInteraction();
    });
    _markDirty();
  }

  void _selectPage(int index) {
    final memo = _activeMemo;
    if (memo == null || index < 0 || index >= memo.pages.length) return;
    setState(() {
      _clearLaserOverlay();
      _activePage = index;
      _clearSelection();
      _clearLassoInteraction();
    });
  }

  void _prevPage() {
    final currentPage = _safeActivePage;
    if (currentPage == 0) return;
    setState(() {
      _clearLaserOverlay();
      _activePage = currentPage - 1;
      _clearSelection();
      _clearLassoInteraction();
    });
    _markDirty();
  }

  void _nextPage() {
    final memo = _activeMemo;
    final currentPage = _safeActivePage;
    if (memo == null || currentPage >= memo.pages.length - 1) return;
    setState(() {
      _clearLaserOverlay();
      _activePage = currentPage + 1;
      _clearSelection();
      _clearLassoInteraction();
    });
    _markDirty();
  }

  void _openMemoPageNavigator() {
    final memo = _activeMemo;
    if (memo == null || memo.pages.isEmpty || !mounted) return;
    final pageCount = memo.pages.length;
    final current = _safeActivePage;
    final jumpCtrl = TextEditingController(text: '${current + 1}');

    Rect? board;
    final boardCtx = _memoEditViewportKey.currentContext;
    final ro = boardCtx?.findRenderObject() as RenderBox?;
    if (ro != null && ro.hasSize) {
      final o = ro.localToGlobal(Offset.zero);
      board = Rect.fromLTWH(o.dx, o.dy, ro.size.width, ro.size.height);
    }

    final hints = memo.pages
        .map(
          (p) =>
              p.strokes.isNotEmpty ||
              p.textBoxes.isNotEmpty ||
              p.placedImages.isNotEmpty,
        )
        .toList();

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, _) {
        return FadeTransition(
          opacity: anim,
          child: _MemoPageNavigatorRouteBody(
            boardRect: board,
            pages: memo.pages,
            paperStyle: _paperStyle,
            pdfDisplayMode: memo.pdfDisplayMode,
            pdfs: _uploadedPdfs,
            pageCount: pageCount,
            currentIndex: current,
            pageHints: hints,
            liveCanvasSize: _liveCanvasSize,
            jumpController: jumpCtrl,
            onSelectIndex: (i) {
              Navigator.pop(ctx);
              _selectPage(i);
            },
            onPrevPage: () {
              Navigator.pop(ctx);
              _prevPage();
            },
            onNextPage: () {
              Navigator.pop(ctx);
              _nextPage();
            },
            onSubmitJump: (raw) => _submitMemoPageJump(ctx, raw, pageCount),
          ),
        );
      },
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 350), jumpCtrl.dispose);
    });
  }

  void _submitMemoPageJump(BuildContext sheetCtx, String raw, int pageCount) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > pageCount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('1~$pageCount 사이 숫자를 입력해 주세요.')));
      return;
    }
    Navigator.pop(sheetCtx);
    _selectPage(n - 1);
  }

  // ── PDF management ───────────────────────────────────────────

  Future<void> _uploadPdf() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'PDF'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final storage = await _resolvePdfStorageDir();
      final pdfDir = storage.$1;
      if (!await pdfDir.exists()) await pdfDir.create(recursive: true);

      final added = <_PdfAsset>[];
      for (final file in result.files) {
        try {
          final fileId =
              'pdf_${DateTime.now().microsecondsSinceEpoch}_${added.length}';
          final safeName = file.name.replaceAll(
            RegExp(r'[^a-zA-Z0-9._가-힣-]'),
            '_',
          );
          final targetPath = '${pdfDir.path}/$fileId-$safeName';
          final copied = await _copyPickedFileToTarget(
            picked: file,
            targetPath: targetPath,
          );
          if (!copied) continue;
          added.add(
            _PdfAsset(
              id: fileId,
              name: file.name,
              path: targetPath,
              addedAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } catch (_) {}
      }

      if (added.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업로드할 수 있는 PDF를 찾지 못했어요.')),
        );
        return;
      }

      final memo = _activeMemo;
      if (memo == null) {
        if (!mounted) return;
        for (final a in added) {
          unawaited(_deleteFileQuietly(a.path));
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('메모를 먼저 선택해 주세요.')));
        return;
      }

      final meta = await _measurePdfForUpload(added.first.path);
      if (meta == null) {
        if (!mounted) return;
        for (final a in added) {
          unawaited(_deleteFileQuietly(a.path));
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF 정보를 읽지 못했어요.')));
        return;
      }

      var displayMode = memo.pdfDisplayMode;
      if (meta.differs && mounted) {
        final choice = await showDialog<_PdfDisplayMode>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('PDF와 메모 규격'),
            content: const Text('PDF 페이지 비율이 메모(√2)와 다릅니다. 어떻게 표시할까요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _PdfDisplayMode.preservePdfAspect),
                child: const Text('PDF 원래 규격 유지'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, _PdfDisplayMode.stretchToMemo),
                child: const Text('메모에 맞게 규격 조정'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (choice == null) {
          for (final a in added) {
            unawaited(_deleteFileQuietly(a.path));
          }
          return;
        }
        displayMode = choice;
      }

      final enriched = <_PdfAsset>[];
      for (var i = 0; i < added.length; i++) {
        final a = added[i];
        final m = i == 0 ? meta : await _measurePdfForUpload(a.path);
        final pc = m?.pageCount ?? 1;
        enriched.add(
          _PdfAsset(
            id: a.id,
            name: a.name,
            path: a.path,
            addedAtMillis: a.addedAtMillis,
            pageCount: pc,
          ),
        );
      }

      setState(() {
        _uploadedPdfs = [..._uploadedPdfs, ...enriched];
        final first = enriched.first;
        final rawPc = first.pageCount ?? 1;
        final pageCount = rawPc < 1 ? 1 : rawPc;
        final insertAt = (_safeActivePage + 1).clamp(0, memo.pages.length);
        final inserted = <_CanvasPage>[
          for (var pi = 0; pi < pageCount; pi++)
            _CanvasPage.createPdfCanvasPage(
              pdfAssetId: first.id,
              pdfPageIndex: pi,
            ),
        ];
        memo.pages.insertAll(insertAt, inserted);
        memo.pdfId = first.id;
        memo.pdfDisplayMode = displayMode;
        _clearLaserOverlay();
        _activePage = insertAt;
      });
      _markDirty();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF ${enriched.length}개 업로드 완료')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
    }
  }

  Future<(Directory, bool)> _resolvePdfStorageDir() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return (Directory('${dir.path}/materials_pdfs'), false);
    } on MissingPluginException {
      return (Directory('${Directory.systemTemp.path}/materials_pdfs'), true);
    }
  }

  Future<bool> _copyPickedFileToTarget({
    required PlatformFile picked,
    required String targetPath,
  }) async {
    try {
      if (picked.bytes != null) {
        await File(targetPath).writeAsBytes(picked.bytes!, flush: true);
        return true;
      }
      if (picked.readStream != null) {
        final sink = File(targetPath).openWrite();
        await picked.readStream!.pipe(sink);
        await sink.close();
        return true;
      }
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) return false;
      final normalized = sourcePath.startsWith('file://')
          ? Uri.parse(sourcePath).toFilePath()
          : sourcePath;
      final source = File(normalized);
      if (!await source.exists()) return false;
      await source.copy(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _memoAspectRatio = 1 / 1.414;
  static const _pdfAspectTolerance = 0.02;

  bool _pdfAspectDiffersFromMemo(double pdfWidthOverHeight) {
    if (pdfWidthOverHeight <= 0) return false;
    final delta =
        (pdfWidthOverHeight - _memoAspectRatio).abs() / _memoAspectRatio;
    return delta > _pdfAspectTolerance;
  }

  Future<({bool differs, int pageCount})?> _measurePdfForUpload(
    String path,
  ) async {
    PdfDocument? document;
    PdfPage? page;
    try {
      await _ensurePdfxRegistration();
      document = await PdfDocument.openFile(path);
      final n = document.pagesCount;
      if (n < 1) return (differs: false, pageCount: 1);
      page = await document.getPage(1);
      final ratio = page.width / page.height;
      return (differs: _pdfAspectDiffersFromMemo(ratio), pageCount: n);
    } catch (_) {
      return null;
    } finally {
      await page?.close();
      await document?.close();
    }
  }

  void _removePdf(String pdfId) {
    final removing = _uploadedPdfs.where((p) => p.id == pdfId).toList();
    if (removing.isEmpty) return;

    final imagePathsToDelete = <String>[];

    setState(() {
      _uploadedPdfs = _uploadedPdfs.where((p) => p.id != pdfId).toList();

      for (final memo in _memos) {
        final isActiveMemo = memo.id == _activeMemoId;
        final oldActive = isActiveMemo ? _safeActivePage : 0;

        final indicesToRemove = <int>[];
        for (var i = 0; i < memo.pages.length; i++) {
          final pg = memo.pages[i];
          if (pg.kind == _CanvasPageKind.pdf && pg.sourcePdfId == pdfId) {
            indicesToRemove.add(i);
            for (final img in pg.placedImages) {
              imagePathsToDelete.add(img.storagePath);
            }
          }
        }

        for (final i in indicesToRemove.reversed) {
          memo.pages.removeAt(i);
        }

        if (memo.pages.isEmpty) {
          memo.pages.add(_CanvasPage.createDefaultMemoPage());
        }

        if (isActiveMemo) {
          final removedBelow = indicesToRemove
              .where((i) => i < oldActive)
              .length;
          _clearLaserOverlay();
          _activePage = (oldActive - removedBelow).clamp(
            0,
            memo.pages.length - 1,
          );
        }

        _repointMemoPrimaryPdfAfterRemoval(memo, pdfId);
      }
    });

    _markDirty();
    for (final pdf in removing) {
      unawaited(_deleteFileQuietly(pdf.path));
    }
    for (final p in imagePathsToDelete) {
      unawaited(_deleteFileQuietly(p));
    }
  }

  Future<void> _deleteFileQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  // ── Lasso, selection, images ─────────────────────────────────

  bool get _hasLassoSelection =>
      _selectedStrokeIds.isNotEmpty ||
      _selectedImageIds.isNotEmpty ||
      _selectedTextIds.isNotEmpty;

  bool _lassoFilterAllowsAny() =>
      _lassoFilterText || _lassoFilterDrawing || _lassoFilterImage;

  void _clearSelection() {
    _selectedStrokeIds.clear();
    _selectedImageIds.clear();
    _selectedTextIds.clear();
    _selBaseBounds = null;
    _selRotationRad = 0;
  }

  void _clearLassoInteraction() {
    _lassoPointerId = null;
    _lassoDrag = _LassoDragKind.idle;
    _lassoPathLocal = null;
    _lassoGestureStartLocal = null;
    _lassoMoveAnchorLocal = null;
    _lassoResizeStrokePointsStart = null;
    _lassoResizeImageNormStart = null;
    _lassoResizeTextNormStart = null;
    _lassoResizeTextFontStart = null;
    _lassoResizeStartAabb = null;
    _lassoMoveStrokePointsStart = null;
    _lassoMoveImageNormStart = null;
    _lassoMoveTextNormStart = null;
    _lassoMoveDidChange = false;
    _lassoResizeDidChange = false;
    _lassoRotateDidChange = false;
    _lassoRotatePivot = null;
    _lassoRotatePointerStartAngle = null;
    _lassoRotateStrokeBaseline = null;
    _lassoRotateTextStartDeg = null;
    _lassoRotateImageStartDeg = null;
    _lassoRotateTextCenterStart = null;
    _lassoRotateImageCenterStart = null;
    _lassoRotateTextNormRectStart = null;
    _lassoRotateImageNormRectStart = null;
    _pendingMoveUndo = null;
    _pendingResizeUndo = null;
    _pendingRotateUndo = null;
    _lassoPendingMarqueePointer = null;
    _lassoPendingMarqueeStart = null;
  }

  /// Recompute `_selBaseBounds` and `_selRotationRad` from the current
  /// selection. Called whenever membership changes (lasso polygon, tap select,
  /// delete, etc).
  void _resetSelectionGeometryFromContent(Size canvasSize) {
    final page = _activeMemoPage;
    if (page == null || !_hasLassoSelection) {
      _selBaseBounds = null;
      _selRotationRad = 0;
      return;
    }

    final corners = _collectSelectionCanvasCorners(page, canvasSize);
    if (corners.isEmpty) {
      _selBaseBounds = _computeContentAabbLocal(canvasSize);
      _selRotationRad = 0;
      return;
    }

    final nText = _selectedTextIds.length;
    final nImg = _selectedImageIds.length;
    final nRot = nText + nImg;

    if (nRot == 0) {
      _selRotationRad = 0;
      _selBaseBounds = _computeContentAabbLocal(canvasSize);
      return;
    }

    double thetaRad;
    Offset pivot;

    if (nRot == 1) {
      _CanvasTextBox? onlyT;
      _PlacedImage? onlyI;
      if (nText == 1) {
        for (final t in page.textBoxes) {
          if (_selectedTextIds.contains(t.id)) {
            onlyT = t;
            break;
          }
        }
      }
      if (nImg == 1 && onlyT == null) {
        for (final img in page.placedImages) {
          if (_selectedImageIds.contains(img.id)) {
            onlyI = img;
            break;
          }
        }
      }
      if (onlyT != null) {
        thetaRad = onlyT.rotationRad;
        pivot = onlyT.rect.toLocalRect(canvasSize).center;
      } else if (onlyI != null) {
        thetaRad = onlyI.rotationRad;
        pivot = onlyI.rect.toLocalRect(canvasSize).center;
      } else {
        _selRotationRad = 0;
        _selBaseBounds = _computeContentAabbLocal(canvasSize);
        return;
      }
    } else {
      thetaRad = _inferCoherentLassoSelectionRotationRad(page);
      if (thetaRad.abs() < 1e-6) {
        _selRotationRad = 0;
        _selBaseBounds = _computeContentAabbLocal(canvasSize);
        return;
      }
      pivot = _rectFromPoints(corners).center;
    }

    _selRotationRad = thetaRad;
    _selBaseBounds = _obbBaseRectForCorners(corners, pivot, thetaRad);
  }

  static Rect _rectFromPoints(Iterable<Offset> pts) {
    final it = pts.iterator;
    if (!it.moveNext()) return Rect.zero;
    var l = it.current.dx;
    var t = it.current.dy;
    var r = l;
    var b = t;
    while (it.moveNext()) {
      final p = it.current;
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  static void _appendRotatedRectCorners(
    Rect r,
    double rotationRad,
    List<Offset> out,
  ) {
    final c = r.center;
    final hx = r.width * 0.5;
    final hy = r.height * 0.5;
    const signs = <(double, double)>[(-1, -1), (1, -1), (1, 1), (-1, 1)];
    for (final sg in signs) {
      final local = Offset(sg.$1 * hx, sg.$2 * hy);
      out.add(c + _rotateDocVector(local, rotationRad));
    }
  }

  List<Offset> _collectSelectionCanvasCorners(_CanvasPage page, Size canvas) {
    final out = <Offset>[];
    for (final id in _selectedStrokeIds) {
      for (final s in page.strokes) {
        if (s.id != id) continue;
        final b = _strokePixelBounds(s).inflate(4);
        out.addAll([b.topLeft, b.topRight, b.bottomRight, b.bottomLeft]);
        break;
      }
    }
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id != id) continue;
        final r = img.rect.toLocalRect(canvas);
        _appendRotatedRectCorners(r, img.rotationRad, out);
        break;
      }
    }
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id != id) continue;
        final r = t.rect.toLocalRect(canvas);
        _appendRotatedRectCorners(r, t.rotationRad, out);
        break;
      }
    }
    return out;
  }

  /// Returns 0 when selected texts/images disagree by more than [_kLassoRotGroupMaxDeg].
  double _inferCoherentLassoSelectionRotationRad(_CanvasPage page) {
    final degs = <double>[];
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          degs.add(t.rotationDeg);
          break;
        }
      }
    }
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id == id) {
          degs.add(img.rotationDeg);
          break;
        }
      }
    }
    if (degs.length < 2) return 0;

    var sx = 0.0;
    var sy = 0.0;
    for (final d in degs) {
      final r = d * math.pi / 180.0;
      sx += math.cos(r);
      sy += math.sin(r);
    }
    final mean = math.atan2(sy, sx);
    const maxSpread = _kLassoRotGroupMaxDeg * math.pi / 180.0;
    for (final d in degs) {
      final r = d * math.pi / 180.0;
      if (_unwrapAngleDelta(r - mean).abs() > maxSpread) {
        return 0;
      }
    }
    return mean;
  }

  static const double _kLassoRotGroupMaxDeg = 5;

  /// Axis-aligned [_selBaseBounds] in canvas px such that rotating it by
  /// [thetaRad] around its center matches the selection OBB for [corners].
  Rect _obbBaseRectForCorners(
    List<Offset> corners,
    Offset initialPivot,
    double thetaRad,
  ) {
    var pivot = initialPivot;
    Rect? last;
    for (var pass = 0; pass < 4; pass++) {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final p in corners) {
        final q = _rotateDocVector(p - pivot, -thetaRad) + pivot;
        minX = math.min(minX, q.dx);
        maxX = math.max(maxX, q.dx);
        minY = math.min(minY, q.dy);
        maxY = math.max(maxY, q.dy);
      }
      final b = Rect.fromLTRB(minX, minY, maxX, maxY);
      if (last != null &&
          (b.center - last.center).distance < 0.2 &&
          (b.width - last.width).abs() < 0.2 &&
          (b.height - last.height).abs() < 0.2) {
        return b;
      }
      last = b;
      pivot = b.center;
    }
    return last ?? Rect.zero;
  }

  /// AABB of all currently selected items in canvas-local px.
  Rect? _computeContentAabbLocal(Size canvas) {
    final page = _activeMemoPage;
    if (page == null || !_hasLassoSelection) return null;
    Rect? u;
    void add(Rect r) {
      u = u == null ? r : u!.expandToInclude(r);
    }

    for (final id in _selectedStrokeIds) {
      for (final s in page.strokes) {
        if (s.id == id) {
          add(_strokePixelBounds(s).inflate(4));
          break;
        }
      }
    }
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id == id) {
          add(img.rect.toLocalRect(canvas));
          break;
        }
      }
    }
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          add(t.rect.toLocalRect(canvas));
          break;
        }
      }
    }
    return u;
  }

  void _showLassoTargetFilterSheet() {
    var textOn = _lassoFilterText;
    var drawingOn = _lassoFilterDrawing;
    var imageOn = _lassoFilterImage;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void trySet({
              required bool nextText,
              required bool nextDrawing,
              required bool nextImage,
            }) {
              if (!nextText && !nextDrawing && !nextImage) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('한 가지 이상의 선택 대상을 켜 주세요.')),
                );
                return;
              }
              setModal(() {
                textOn = nextText;
                drawingOn = nextDrawing;
                imageOn = nextImage;
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '선택 대상',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('텍스트'),
                      value: textOn,
                      onChanged: (v) => trySet(
                        nextText: v ?? false,
                        nextDrawing: drawingOn,
                        nextImage: imageOn,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('필기'),
                      value: drawingOn,
                      onChanged: (v) => trySet(
                        nextText: textOn,
                        nextDrawing: v ?? false,
                        nextImage: imageOn,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('이미지'),
                      value: imageOn,
                      onChanged: (v) => trySet(
                        nextText: textOn,
                        nextDrawing: drawingOn,
                        nextImage: v ?? false,
                      ),
                    ),
                    if (textOn) ...[
                      const SizedBox(height: 8),
                      Text(
                        '텍스트 박스는 상단 도구의 「텍스트」(Aa)를 선택한 뒤 캔버스를 탭해 만들 수 있어요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.subText.withValues(alpha: 0.95),
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('닫기'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _lassoFilterText = textOn;
        _lassoFilterDrawing = drawingOn;
        _lassoFilterImage = imageOn;
        _clearSelection();
        _clearLassoInteraction();
      });
      _markDirty();
    });
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 < 1e-6) return (p - a).distance;
    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / ab2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  static Rect _strokePixelBounds(_Stroke s) {
    if (s.points.isEmpty) {
      return Rect.zero;
    }
    var minX = s.points.first.dx;
    var minY = s.points.first.dy;
    var maxX = s.points.first.dx;
    var maxY = s.points.first.dy;
    for (final p in s.points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _strokeHitTest(_Stroke s, Offset local, double padding) {
    if (!_lassoFilterDrawing) return false;
    if (!_strokeToolIsPersistedInk(s.tool) || s.points.length < 2) {
      return false;
    }
    final w = s.width * 0.5 + padding;
    for (var i = 0; i < s.points.length - 1; i++) {
      if (_distToSegment(local, s.points[i], s.points[i + 1]) <= w) {
        return true;
      }
    }
    return false;
  }

  String? _hitTestTopStrokeId(Offset local, _CanvasPage page) {
    for (var i = page.strokes.length - 1; i >= 0; i--) {
      final s = page.strokes[i];
      if (_strokeHitTest(s, local, 14)) return s.id;
    }
    return null;
  }

  String? _hitTestTopImageId(Offset local, Size canvas, _CanvasPage page) {
    if (!_lassoFilterImage) return null;
    for (var i = page.placedImages.length - 1; i >= 0; i--) {
      final img = page.placedImages[i];
      final rect = img.rect.toLocalRect(canvas);
      if (_rotatedRectContainsPoint(rect, img.rotationRad, local)) {
        return img.id;
      }
    }
    return null;
  }

  String? _hitTestTopTextId(
    Offset local,
    Size canvas,
    _CanvasPage page, {
    bool respectLassoFilter = true,
  }) {
    if (respectLassoFilter && !_lassoFilterText) return null;
    for (var i = page.textBoxes.length - 1; i >= 0; i--) {
      final t = page.textBoxes[i];
      final rect = t.rect.toLocalRect(canvas);
      if (_rotatedRectContainsPoint(rect, t.rotationRad, local)) return t.id;
    }
    return null;
  }

  /// True when [doc] is not over a stroke / image / text hit target (lasso long-press).
  bool _lassoLongPressPointIsClearOfObjects(
    Offset doc,
    Size canvasSize,
    _CanvasPage page,
  ) {
    if (_hitTestTopImageId(doc, canvasSize, page) != null) return false;
    if (_hitTestTopTextId(doc, canvasSize, page, respectLassoFilter: true) !=
        null) {
      return false;
    }
    if (_hitTestTopStrokeId(doc, page) != null) return false;
    return true;
  }

  /// 미니바(텍스트 박스 위) + 약간의 여백까지 텍스트 도구 히트로 인정.
  void _selectTopAt(Offset local, Size canvas, _CanvasPage page) {
    _clearSelection();
    final img = _hitTestTopImageId(local, canvas, page);
    if (img != null) {
      _selectedImageIds.add(img);
      _resetSelectionGeometryFromContent(canvas);
      return;
    }
    final tx = _hitTestTopTextId(local, canvas, page);
    if (tx != null) {
      _selectedTextIds.add(tx);
      _resetSelectionGeometryFromContent(canvas);
      return;
    }
    final st = _hitTestTopStrokeId(local, page);
    if (st != null) {
      _selectedStrokeIds.add(st);
      _resetSelectionGeometryFromContent(canvas);
    }
  }

  /// The current rendered selection rectangle in canvas-local px (un-rotated).
  ///
  /// Returns the cached OBB base when present (so the box doesn't expand into
  /// a fat AABB while content is being rotated). Falls back to a fresh AABB
  /// over the selected content (e.g. immediately after a lasso completes
  /// before geometry is committed).
  Rect? _selectionBoundsLocal(Size canvas) {
    final base = _selBaseBounds;
    if (base != null) return base;
    if (!_hasLassoSelection) return null;
    return _computeContentAabbLocal(canvas);
  }

  /// Map a screen-local point into the selection's un-rotated frame so we can
  /// hit-test handles/fabs against the cached axis-aligned [_selBaseBounds].
  Offset _selectionUnrotatedPoint(Offset local) {
    final bounds = _selBaseBounds;
    if (bounds == null || _selRotationRad == 0) return local;
    return _rotateDocVector(local - bounds.center, -_selRotationRad) +
        bounds.center;
  }

  bool _hitTestLassoRotateKnob(Offset local, Rect? bounds) {
    if (bounds == null) return false;
    final p = _selectionUnrotatedPoint(local);
    final c = _studioRotateKnobCenter(bounds);
    return (p - c).distance <= _studioSelRotateR + 6;
  }

  static const double _lassoCornerHit = 12;
  static const double _lassoEdgeHit = 10;

  Rect _lassoDeleteFabRect(Rect bounds) =>
      _studioSelectionDeleteFabRect(bounds);

  Rect _lassoCopyFabRect(Rect bounds) => _studioSelectionCopyFabRect(bounds);

  /// Lasso bbox resize: 0–3 = corners TL,TR,BR,BL; 4–7 = edges T,R,B,L.
  int? _hitTestLassoResizeHandle(Offset local, Rect bounds) {
    final p = _selectionUnrotatedPoint(local);
    const ch = _lassoCornerHit;
    const eh = _lassoEdgeHit;
    final corners = <(int, Offset)>[
      (0, bounds.topLeft),
      (1, bounds.topRight),
      (2, bounds.bottomRight),
      (3, bounds.bottomLeft),
    ];
    for (final (i, c) in corners) {
      if ((p - c).distance <= ch) return i;
    }
    if ((p.dy - bounds.top).abs() <= eh &&
        p.dx > bounds.left + ch &&
        p.dx < bounds.right - ch) {
      return 4;
    }
    if ((p.dx - bounds.right).abs() <= eh &&
        p.dy > bounds.top + ch &&
        p.dy < bounds.bottom - ch) {
      return 5;
    }
    if ((p.dy - bounds.bottom).abs() <= eh &&
        p.dx > bounds.left + ch &&
        p.dx < bounds.right - ch) {
      return 6;
    }
    if ((p.dx - bounds.left).abs() <= eh &&
        p.dy > bounds.top + ch &&
        p.dy < bounds.bottom - ch) {
      return 7;
    }
    return null;
  }

  bool _hitTestDeleteFab(Offset local, Rect? bounds) {
    if (bounds == null) return false;
    return _lassoDeleteFabRect(
      bounds,
    ).contains(_selectionUnrotatedPoint(local));
  }

  bool _hitTestCopyFab(Offset local, Rect? bounds) {
    if (bounds == null) return false;
    return _lassoCopyFabRect(bounds).contains(_selectionUnrotatedPoint(local));
  }

  /// Group resize is available whenever there is any lasso selection —
  /// strokes, images, and text boxes are scaled together around the
  /// drag-anchor corner/edge.
  bool _canResizeSelection() {
    return _hasLassoSelection;
  }

  Future<void> _addImageToCanvas() async {
    final page = _activeMemoPage;
    if (page == null) return;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      final srcPath = f.path;
      if (srcPath == null || srcPath.isEmpty) return;

      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${dir.path}/materials_images');
      await destDir.create(recursive: true);
      final id = _uuid.v4();
      final lower = f.name.toLowerCase();
      final ext = lower.endsWith('.png')
          ? '.png'
          : lower.endsWith('.webp')
          ? '.webp'
          : lower.endsWith('.gif')
          ? '.gif'
          : '.jpg';
      final destPath = '${destDir.path}/$id$ext';
      await File(srcPath).copy(destPath);

      if (!mounted) return;
      setState(() {
        page.pushPageVisualUndo(_PageVisualStateSnapshot.fromPage(page));
        page.placedImages.add(
          _PlacedImage(
            id: id,
            storagePath: destPath,
            rect: _NormRect(left: 0.2, top: 0.25, width: 0.45, height: 0.28),
            zIndex: page.placedImages.length,
          ),
        );
        _clearSelection();
        _selectedImageIds.add(id);
      });
      _markDirty();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미지를 추가하지 못했어요.')));
    }
  }

  String _addTextBoxAtCanvasPoint(
    Offset local,
    Size canvasSize,
    _CanvasPage page,
  ) {
    final ts = _settingsFor(_ToolType.text);
    final fontSize = ts.width.clamp(8.0, 72.0);

    // Start as a snug single-line box so it doesn't read as a fat capsule.
    // Width: ~8 characters at current font size; height: one text line + padding.
    final cw = canvasSize.width > 0 ? canvasSize.width : 700.0;
    final ch = canvasSize.height > 0 ? canvasSize.height : 990.0;
    final approxCharW = fontSize * 0.62;
    final approxLineH =
        fontSize * _kCanvasTextLineHeight +
        _kTextInlineVerticalPadding * 2 +
        8; // matches TextField + descender headroom
    final approxLineW = approxCharW * 8 + _kTextInlineHorizontalPadding * 2;
    var nw = (approxLineW / cw).clamp(0.10, 0.55);
    var nh = (approxLineH / ch).clamp(0.025, 0.20);

    var nx = (local.dx / cw) - nw * 0.5;
    var ny = (local.dy / ch) - nh * 0.5;
    nx = nx.clamp(0.02, 1.0 - nw - 0.02);
    ny = ny.clamp(0.02, 1.0 - nh - 0.02);
    final id = _uuid.v4();
    if (!mounted) return id;
    setState(() {
      page.pushLayoutUndo(
        _LassoLayoutSnapshot(
          strokePoints: {},
          imageRects: {},
          textRects: {},
          textBodies: {},
          fullTextBoxesJson: page.textBoxes
              .map((x) => x.toJson(emitPageId: page.id))
              .toList(),
        ),
      );
      page.textBoxes.add(
        _CanvasTextBox(
          id: id,
          pageId: page.id,
          text: '',
          rect: _NormRect(left: nx, top: ny, width: nw, height: nh),
          fontSize: fontSize,
          bold: ts.bold,
          italic: ts.italic,
          underline: ts.textUnderline,
          fontFamily: ts.textFontFamily,
          color: ts.color,
          textAlignIndex: ts.textAlignIndex.clamp(0, 2),
          hasBackground: ts.textBoxNextHasBackground,
          backgroundColor: ts.textBoxNextBackgroundColor,
          hasBorder: ts.textBoxNextHasBorder,
          borderColor: ts.textBoxNextBorderColor,
          // Newly created box follows typed content (Goodnotes style) until
          // the user explicitly grabs a resize handle.
          autoSize: true,
        ),
      );
      _clearSelection();
      _selectedTextIds.add(id);
    });
    _markDirty();
    return id;
  }

  Future<String> _copyImageToMaterialsDir(String srcPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory('${dir.path}/materials_images');
    await destDir.create(recursive: true);
    final id = _uuid.v4();
    final lower = srcPath.toLowerCase();
    final ext = lower.endsWith('.png')
        ? '.png'
        : lower.endsWith('.webp')
        ? '.webp'
        : lower.endsWith('.gif')
        ? '.gif'
        : '.jpg';
    final destPath = '${destDir.path}/$id$ext';
    await File(srcPath).copy(destPath);
    return destPath;
  }

  void _captureStudioClipboard(_CanvasPage page, Offset anchorDoc) {
    final sm = <Map<String, dynamic>>[];
    for (final id in _selectedStrokeIds) {
      for (final s in page.strokes) {
        if (s.id == id) {
          sm.add(s.toJson());
          break;
        }
      }
    }
    final tm = <Map<String, dynamic>>[];
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          tm.add(t.toJson(emitPageId: page.id));
          break;
        }
      }
    }
    final im = <Map<String, dynamic>>[];
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id == id) {
          im.add(img.toJson());
          break;
        }
      }
    }
    _studioClipboard = _StudioClipboardPayload(
      anchorDoc: anchorDoc,
      strokeMaps: sm,
      textMaps: tm,
      imageMaps: im,
    );
  }

  _LassoLayoutSnapshot _layoutSnapshotForSelected(_CanvasPage page) {
    final strokeSnap = <String, List<Offset>>{};
    for (final id in _selectedStrokeIds) {
      for (final s in page.strokes) {
        if (s.id == id) {
          strokeSnap[id] = s.points.map((e) => Offset(e.dx, e.dy)).toList();
          break;
        }
      }
    }
    final imgSnap = <String, _NormRect>{};
    final imgRot = <String, double>{};
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id == id) {
          imgSnap[id] = img.rect.copy();
          imgRot[id] = img.rotationDeg;
          break;
        }
      }
    }
    final textSnap = <String, _NormRect>{};
    final textBodies = <String, String>{};
    final textRot = <String, double>{};
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          textSnap[id] = t.rect.copy();
          textBodies[id] = t.text;
          textRot[id] = t.rotationDeg;
          break;
        }
      }
    }
    return _LassoLayoutSnapshot(
      strokePoints: {
        for (final e in strokeSnap.entries)
          e.key: e.value.map((o) => Offset(o.dx, o.dy)).toList(),
      },
      imageRects: {for (final e in imgSnap.entries) e.key: e.value.copy()},
      textRects: {for (final e in textSnap.entries) e.key: e.value.copy()},
      textBodies: textBodies,
      textRotationDeg: textRot,
      imageRotationDeg: imgRot,
    );
  }

  Future<void> _duplicateLassoSelectionByDelta(
    _CanvasPage page,
    Offset deltaDoc,
    Size canvasSize,
  ) async {
    final w = canvasSize.width;
    final h = canvasSize.height;
    if (w <= 0 || h <= 0) return;
    page.pushPageVisualUndo(_PageVisualStateSnapshot.fromPage(page));
    final newStrokeIds = <String>[];
    final newTextIds = <String>[];
    final newImageIds = <String>[];
    for (final id in _selectedStrokeIds.toList()) {
      for (final s in page.strokes) {
        if (s.id != id) continue;
        final m = s.toJson();
        m['id'] = _uuid.v4();
        final pts = (m['points'] as List<dynamic>?) ?? const [];
        final nextPts = <List<double>>[];
        for (final p in pts) {
          if (p is List && p.length == 2) {
            nextPts.add([
              (p[0] as num).toDouble() + deltaDoc.dx,
              (p[1] as num).toDouble() + deltaDoc.dy,
            ]);
          }
        }
        m['points'] = nextPts;
        final copy = _Stroke.fromJson(m);
        newStrokeIds.add(copy.id);
        page.strokes.add(copy);
        break;
      }
    }
    for (final id in _selectedTextIds.toList()) {
      for (final t in page.textBoxes) {
        if (t.id != id) continue;
        final m = t.toJson(emitPageId: page.id);
        m['id'] = _uuid.v4();
        final rect = Map<String, dynamic>.from(
          m['rect'] as Map<String, dynamic>? ?? {},
        );
        final nl = ((rect['l'] as num?)?.toDouble() ?? 0) + deltaDoc.dx / w;
        final nt = ((rect['t'] as num?)?.toDouble() ?? 0) + deltaDoc.dy / h;
        rect['l'] = nl.clamp(0.0, 1.0);
        rect['t'] = nt.clamp(0.0, 1.0);
        m['rect'] = rect;
        final copy = _CanvasTextBox.fromJson(m, pageId: page.id);
        newTextIds.add(copy.id);
        page.textBoxes.add(copy);
        break;
      }
    }
    for (final id in _selectedImageIds.toList()) {
      for (final img in page.placedImages) {
        if (img.id != id) continue;
        try {
          final dest = await _copyImageToMaterialsDir(img.storagePath);
          final m = img.toJson();
          m['id'] = _uuid.v4();
          m['path'] = dest;
          final rect = Map<String, dynamic>.from(
            m['rect'] as Map<String, dynamic>? ?? {},
          );
          final nl = ((rect['l'] as num?)?.toDouble() ?? 0) + deltaDoc.dx / w;
          final nt = ((rect['t'] as num?)?.toDouble() ?? 0) + deltaDoc.dy / h;
          rect['l'] = nl.clamp(0.0, 1.0);
          rect['t'] = nt.clamp(0.0, 1.0);
          m['rect'] = rect;
          final copy = _PlacedImage.fromJson(m);
          newImageIds.add(copy.id);
          page.placedImages.add(copy);
        } catch (_) {}
        break;
      }
    }
    page.redoStack.clear();
    _clearSelection();
    for (final id in newStrokeIds) {
      _selectedStrokeIds.add(id);
    }
    for (final id in newTextIds) {
      _selectedTextIds.add(id);
    }
    for (final id in newImageIds) {
      _selectedImageIds.add(id);
    }
    _resetSelectionGeometryFromContent(canvasSize);
    if (mounted) {
      setState(() {});
      _annotationRepaint.value++;
      _textLayerRepaint.value++;
      _markDirty();
    }
  }

  Future<void> _lassoCopyToClipboardAndDuplicateNearby(Size canvasSize) async {
    final page = _activeMemoPage;
    if (page == null || !_hasLassoSelection) return;
    final b = _selectionBoundsLocal(canvasSize);
    if (b == null) return;
    _captureStudioClipboard(page, b.center);
    await _duplicateLassoSelectionByDelta(
      page,
      const Offset(14, 14),
      canvasSize,
    );
  }

  Future<void> _pasteStudioClipboardAt(Offset docPoint, Size canvasSize) async {
    final clip = _studioClipboard;
    final page = _activeMemoPage;
    if (clip == null || page == null) return;
    page.pushPageVisualUndo(_PageVisualStateSnapshot.fromPage(page));
    final w = canvasSize.width;
    final h = canvasSize.height;
    final delta = docPoint - clip.anchorDoc;
    final newStrokeIds = <String>[];
    final newTextIds = <String>[];
    final newImageIds = <String>[];
    for (final m in clip.strokeMaps) {
      final mm = Map<String, dynamic>.from(m);
      mm['id'] = _uuid.v4();
      final pts = (mm['points'] as List<dynamic>?) ?? const [];
      final nextPts = <List<double>>[];
      for (final p in pts) {
        if (p is List && p.length == 2) {
          nextPts.add([
            (p[0] as num).toDouble() + delta.dx,
            (p[1] as num).toDouble() + delta.dy,
          ]);
        }
      }
      mm['points'] = nextPts;
      final s = _Stroke.fromJson(mm);
      newStrokeIds.add(s.id);
      page.strokes.add(s);
    }
    for (final m in clip.textMaps) {
      final mm = Map<String, dynamic>.from(m);
      mm['id'] = _uuid.v4();
      final rect = Map<String, dynamic>.from(
        mm['rect'] as Map<String, dynamic>? ?? {},
      );
      final nl = ((rect['l'] as num?)?.toDouble() ?? 0) + delta.dx / w;
      final nt = ((rect['t'] as num?)?.toDouble() ?? 0) + delta.dy / h;
      rect['l'] = nl.clamp(0.0, 1.0);
      rect['t'] = nt.clamp(0.0, 1.0);
      mm['rect'] = rect;
      final t = _CanvasTextBox.fromJson(mm, pageId: page.id);
      newTextIds.add(t.id);
      page.textBoxes.add(t);
    }
    for (final m in clip.imageMaps) {
      try {
        final src = m['path'] as String? ?? '';
        if (src.isEmpty) continue;
        final dest = await _copyImageToMaterialsDir(src);
        final mm = Map<String, dynamic>.from(m);
        mm['id'] = _uuid.v4();
        mm['path'] = dest;
        final rect = Map<String, dynamic>.from(
          mm['rect'] as Map<String, dynamic>? ?? {},
        );
        final nl = ((rect['l'] as num?)?.toDouble() ?? 0) + delta.dx / w;
        final nt = ((rect['t'] as num?)?.toDouble() ?? 0) + delta.dy / h;
        rect['l'] = nl.clamp(0.0, 1.0);
        rect['t'] = nt.clamp(0.0, 1.0);
        mm['rect'] = rect;
        final img = _PlacedImage.fromJson(mm);
        newImageIds.add(img.id);
        page.placedImages.add(img);
      } catch (_) {}
    }
    page.redoStack.clear();
    _clearSelection();
    for (final id in newStrokeIds) {
      _selectedStrokeIds.add(id);
    }
    for (final id in newTextIds) {
      _selectedTextIds.add(id);
    }
    for (final id in newImageIds) {
      _selectedImageIds.add(id);
    }
    _resetSelectionGeometryFromContent(canvasSize);
    if (mounted) {
      setState(() {});
      _annotationRepaint.value++;
      _textLayerRepaint.value++;
      _markDirty();
    }
  }

  void _deleteSelectedObjects() {
    final page = _activeMemoPage;
    if (page == null) return;
    final pathsToDelete = <String>[];
    page.pushPageVisualUndo(_PageVisualStateSnapshot.fromPage(page));
    setState(() {
      page.strokes.removeWhere((s) {
        if (_selectedStrokeIds.contains(s.id)) {
          return true;
        }
        return false;
      });
      page.placedImages.removeWhere((img) {
        if (_selectedImageIds.contains(img.id)) {
          pathsToDelete.add(img.storagePath);
          return true;
        }
        return false;
      });
      page.textBoxes.removeWhere((t) => _selectedTextIds.contains(t.id));
      _clearSelection();
      _clearLassoInteraction();
    });
    for (final p in pathsToDelete) {
      unawaited(_deleteFileQuietly(p));
    }
    _markDirty();
  }

  void _applyLassoPolygonSelection(
    List<Offset> poly,
    Size canvas,
    _CanvasPage page,
  ) {
    _clearSelection();
    if (poly.length < 3) return;

    if (_lassoFilterDrawing) {
      for (final s in page.strokes) {
        if (!_strokeToolIsPersistedInk(s.tool)) continue;
        if (_strokeTouchedByPolygon(s, poly)) {
          _selectedStrokeIds.add(s.id);
        }
      }
    }
    if (_lassoFilterImage) {
      for (final img in page.placedImages) {
        final r = img.rect.toLocalRect(canvas);
        if (_pointInPolygon(r.center, poly) ||
            _polygonIntersectsRotatedRect(poly, r, img.rotationRad)) {
          _selectedImageIds.add(img.id);
        }
      }
    }
    if (_lassoFilterText) {
      for (final t in page.textBoxes) {
        final r = t.rect.toLocalRect(canvas);
        if (_pointInPolygon(r.center, poly) ||
            _polygonIntersectsRotatedRect(poly, r, t.rotationRad)) {
          _selectedTextIds.add(t.id);
        }
      }
    }

    _resetSelectionGeometryFromContent(canvas);
  }

  void _lassoPointerDown(PointerDownEvent event, Size canvasSize) {
    _pointerCanvasSize = canvasSize;
    _beginPageSwipe(event);
    // A second finger just arrived: cancel any pending one-finger marquee so
    // the existing selection survives the two-finger zoom/pan.
    if (_isPageSwipeActive && _lassoPendingMarqueePointer != null) {
      _lassoPendingMarqueePointer = null;
      _lassoPendingMarqueeStart = null;
    }
    if (_isPageSwipeActive) return;
    if (!_lassoFilterAllowsAny()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올가미로 선택할 대상 유형을 한 가지 이상 켜 주세요.')),
      );
      return;
    }
    if (_lassoPointerId != null) return;
    final page = _activeMemoPage;
    if (page == null) return;

    final rawLocal = event.localPosition;
    final local = _documentPointFromPointer(rawLocal, canvasSize);
    _recordDebugPointer(rawLocal, canvasSize);
    final bounds = _selectionBoundsLocal(canvasSize);

    if (_tool == _ToolType.lasso &&
        bounds != null &&
        _hasLassoSelection &&
        _hitTestCopyFab(local, bounds)) {
      unawaited(_lassoCopyToClipboardAndDuplicateNearby(canvasSize));
      return;
    }

    if (_tool == _ToolType.lasso &&
        bounds != null &&
        _hitTestDeleteFab(local, bounds)) {
      _deleteSelectedObjects();
      return;
    }

    if (_tool == _ToolType.lasso &&
        bounds != null &&
        _hasLassoSelection &&
        _hitTestLassoRotateKnob(local, bounds)) {
      _lassoPointerId = event.pointer;
      _lassoDrag = _LassoDragKind.rotate;
      final pivot = bounds.center;
      _lassoRotatePivot = pivot;
      _lassoRotatePointerStartAngle = math.atan2(
        local.dy - pivot.dy,
        local.dx - pivot.dx,
      );
      _lassoRotateBoxStartRad = _selRotationRad;
      final strokeBase = <String, List<Offset>>{};
      for (final id in _selectedStrokeIds) {
        for (final s in page.strokes) {
          if (s.id == id) {
            strokeBase[id] = s.points.map((e) => Offset(e.dx, e.dy)).toList();
            break;
          }
        }
      }
      _lassoRotateStrokeBaseline = strokeBase;
      final t0 = <String, double>{};
      final tc = <String, Offset>{};
      for (final id in _selectedTextIds) {
        for (final t in page.textBoxes) {
          if (t.id == id) {
            t0[id] = t.rotationDeg;
            tc[id] = t.rect.toLocalRect(canvasSize).center;
            break;
          }
        }
      }
      _lassoRotateTextStartDeg = t0;
      _lassoRotateTextCenterStart = tc;
      final i0 = <String, double>{};
      final ic = <String, Offset>{};
      for (final id in _selectedImageIds) {
        for (final img in page.placedImages) {
          if (img.id == id) {
            i0[id] = img.rotationDeg;
            ic[id] = img.rect.toLocalRect(canvasSize).center;
            break;
          }
        }
      }
      _lassoRotateImageStartDeg = i0;
      _lassoRotateImageCenterStart = ic;
      final trn = <String, _NormRect>{};
      for (final id in _selectedTextIds) {
        for (final t in page.textBoxes) {
          if (t.id == id) {
            trn[id] = t.rect.copy();
            break;
          }
        }
      }
      _lassoRotateTextNormRectStart = trn;
      final irn = <String, _NormRect>{};
      for (final id in _selectedImageIds) {
        for (final img in page.placedImages) {
          if (img.id == id) {
            irn[id] = img.rect.copy();
            break;
          }
        }
      }
      _lassoRotateImageNormRectStart = irn;
      _pendingRotateUndo = _layoutSnapshotForSelected(page);
      _lassoRotateDidChange = false;
      _syncInteractiveViewerGestureAvailability();
      return;
    }

    if (_tool == _ToolType.lasso &&
        bounds != null &&
        _hasLassoSelection &&
        _canResizeSelection()) {
      final c = _hitTestLassoResizeHandle(local, bounds);
      if (c != null) {
        _lassoPointerId = event.pointer;
        _lassoDrag = _LassoDragKind.resize;
        _lassoResizeCorner = c;
        _lassoResizeStartAabb = bounds;
        // Snapshot every selected child so the painter can rebuild geometry
        // every frame from a stable baseline.
        final strokeBase = <String, List<Offset>>{};
        for (final id in _selectedStrokeIds) {
          for (final s in page.strokes) {
            if (s.id == id) {
              strokeBase[id] = s.points.map((e) => Offset(e.dx, e.dy)).toList();
              break;
            }
          }
        }
        _lassoResizeStrokePointsStart = strokeBase;
        final imgBase = <String, _NormRect>{};
        for (final id in _selectedImageIds) {
          for (final img in page.placedImages) {
            if (img.id == id) {
              imgBase[id] = img.rect.copy();
              break;
            }
          }
        }
        _lassoResizeImageNormStart = imgBase;
        final textBase = <String, _NormRect>{};
        final textFontBase = <String, double>{};
        for (final id in _selectedTextIds) {
          for (final t in page.textBoxes) {
            if (t.id == id) {
              textBase[id] = t.rect.copy();
              textFontBase[id] = t.fontSize;
              // Group resize scales each text box's font with the box, so
              // the box must commit to user-controlled sizing afterwards
              // (the new size, not auto-fitted text width).
              t.autoSize = false;
              break;
            }
          }
        }
        _lassoResizeTextNormStart = textBase;
        _lassoResizeTextFontStart = textFontBase;
        _pendingResizeUndo = _layoutSnapshotForSelected(page);
        _lassoResizeDidChange = false;
        _syncInteractiveViewerGestureAvailability();
        return;
      }
    }

    if (_tool == _ToolType.lasso && _hasLassoSelection && bounds != null) {
      // Inside the (possibly rotated) selection rect → start a move drag.
      final probe = _selectionUnrotatedPoint(local);
      if (bounds.inflate(8).contains(probe)) {
        _beginLassoMoveDrag(event, local, page);
        return;
      }
    }

    // Single-object hit test BEFORE marquee: if the pointer lands directly
    // on a text box / image / stroke, promote it to the new selection and
    // start dragging it immediately. This avoids the surprising "tap on
    // text box → marquee resets selection and waits for movement" flow.
    // Priority: text > image > stroke, matching the user-facing object
    // stack order.
    if (_tool == _ToolType.lasso) {
      final hitText = _hitTestTopTextId(local, canvasSize, page);
      final hitImage = hitText == null
          ? _hitTestTopImageId(local, canvasSize, page)
          : null;
      final hitStroke = (hitText == null && hitImage == null)
          ? _hitTestTopStrokeId(local, page)
          : null;
      if (hitText != null || hitImage != null || hitStroke != null) {
        setState(() {
          _clearSelection();
          if (hitText != null) {
            _selectedTextIds.add(hitText);
          } else if (hitImage != null) {
            _selectedImageIds.add(hitImage);
          } else if (hitStroke != null) {
            _selectedStrokeIds.add(hitStroke);
          }
          _resetSelectionGeometryFromContent(canvasSize);
        });
        _beginLassoMoveDrag(event, local, page);
        return;
      }
    }

    // Defer the marquee start until movement is confirmed. If a second finger
    // lands first the pending state is cancelled so the existing selection
    // survives the two-finger gesture.
    _lassoPointerId = event.pointer;
    _lassoDrag = _LassoDragKind.idle;
    _lassoPendingMarqueePointer = event.pointer;
    _lassoPendingMarqueeStart = local;
    _syncInteractiveViewerGestureAvailability();
  }

  /// Common entry point that arms a lasso move drag from the current
  /// selection: snapshots the affected strokes / images / text rects so
  /// `_lassoPointerMove` can recompute geometry every frame from a stable
  /// baseline, and registers a single undo snapshot for the whole drag.
  void _beginLassoMoveDrag(
    PointerDownEvent event,
    Offset local,
    _CanvasPage page,
  ) {
    _lassoPointerId = event.pointer;
    _lassoDrag = _LassoDragKind.move;
    _lassoMoveAnchorLocal = local;
    _pendingMoveUndo = _layoutSnapshotForSelected(page);
    final strokeSnap = <String, List<Offset>>{};
    for (final id in _selectedStrokeIds) {
      for (final s in page.strokes) {
        if (s.id == id) {
          strokeSnap[id] = s.points.map((e) => Offset(e.dx, e.dy)).toList();
          break;
        }
      }
    }
    _lassoMoveStrokePointsStart = strokeSnap;
    final imgSnap = <String, _NormRect>{};
    for (final id in _selectedImageIds) {
      for (final img in page.placedImages) {
        if (img.id == id) {
          imgSnap[id] = img.rect.copy();
          break;
        }
      }
    }
    _lassoMoveImageNormStart = imgSnap;
    final textSnap = <String, _NormRect>{};
    for (final id in _selectedTextIds) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          textSnap[id] = t.rect.copy();
          break;
        }
      }
    }
    _lassoMoveTextNormStart = textSnap;
    _lassoMoveDidChange = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _lassoPointerMove(PointerMoveEvent event, Size canvasSize) {
    _updatePageSwipe(event);
    if (_lassoPointerId != event.pointer) return;
    final page = _activeMemoPage;
    if (page == null) return;
    final local = _documentPointFromPointer(event.localPosition, canvasSize);
    _recordDebugPointer(event.localPosition, canvasSize);
    final w = canvasSize.width;
    final h = canvasSize.height;

    // Promote pending one-finger touch into a marquee once movement is
    // confirmed. Skipped while a two-finger gesture is in progress.
    if (_lassoDrag == _LassoDragKind.idle &&
        _lassoPendingMarqueePointer == event.pointer &&
        _lassoPendingMarqueeStart != null) {
      final start = _lassoPendingMarqueeStart!;
      if ((local - start).distance >= _kLassoMarqueeStartSlop) {
        _lassoDrag = _LassoDragKind.marquee;
        _lassoGestureStartLocal = start;
        _lassoPathLocal = [start, local];
        _lassoPendingMarqueePointer = null;
        _lassoPendingMarqueeStart = null;
        _clearSelection();
      }
    }

    switch (_lassoDrag) {
      case _LassoDragKind.idle:
        break;
      case _LassoDragKind.marquee:
        final pts = _lassoPathLocal;
        if (pts != null && pts.isNotEmpty) {
          final last = pts.last;
          if ((local - last).distance > 0.35) {
            pts.add(local);
            _cancelCanvasLongPressTimer();
          }
        }
        setState(() {});
        break;
      case _LassoDragKind.move:
        _lassoMoveDidChange = true;
        final anchor = _lassoMoveAnchorLocal;
        if (anchor == null) break;
        final total = local - anchor;
        final strokeStart = _lassoMoveStrokePointsStart;
        if (strokeStart != null) {
          for (final s in page.strokes) {
            final snap = strokeStart[s.id];
            if (snap == null) continue;
            for (var i = 0; i < s.points.length && i < snap.length; i++) {
              s.points[i] = snap[i] + total;
            }
          }
        }
        final imgStart = _lassoMoveImageNormStart;
        if (imgStart != null) {
          for (final img in page.placedImages) {
            final r0 = imgStart[img.id];
            if (r0 == null) continue;
            img.rect
              ..left = (r0.left + total.dx / w).clamp(0.0, 1.0 - r0.width)
              ..top = (r0.top + total.dy / h).clamp(0.0, 1.0 - r0.height);
          }
        }
        final textStart = _lassoMoveTextNormStart;
        if (textStart != null) {
          for (final t in page.textBoxes) {
            final r0 = textStart[t.id];
            if (r0 == null) continue;
            t.rect
              ..left = (r0.left + total.dx / w).clamp(0.0, 1.0 - r0.width)
              ..top = (r0.top + total.dy / h).clamp(0.0, 1.0 - r0.height);
          }
        }
        // Slide the cached OBB so handles/chrome stick to the moving content.
        final baseShifted = _selBaseBounds?.shift(total);
        if (baseShifted != null) {
          _selBaseBounds = baseShifted;
          _lassoMoveAnchorLocal = local;
          // Re-snapshot every per-child rect under the new anchor so the
          // next move tick continues from the just-applied position.
          if (strokeStart != null) {
            for (final s in page.strokes) {
              final snap = strokeStart[s.id];
              if (snap == null) continue;
              strokeStart[s.id] = s.points
                  .map((p) => Offset(p.dx, p.dy))
                  .toList();
            }
          }
          if (imgStart != null) {
            for (final img in page.placedImages) {
              if (!imgStart.containsKey(img.id)) continue;
              imgStart[img.id] = img.rect.copy();
            }
          }
          if (textStart != null) {
            for (final t in page.textBoxes) {
              if (!textStart.containsKey(t.id)) continue;
              textStart[t.id] = t.rect.copy();
            }
          }
        }
        setState(() {});
        break;
      case _LassoDragKind.rotate:
        _lassoRotateDidChange = true;
        final pivot = _lassoRotatePivot;
        final base =
            _lassoRotateStrokeBaseline ?? const <String, List<Offset>>{};
        final startAng = _lassoRotatePointerStartAngle;
        final t0 = _lassoRotateTextStartDeg;
        final tc = _lassoRotateTextCenterStart;
        final trn0 = _lassoRotateTextNormRectStart;
        final i0 = _lassoRotateImageStartDeg;
        final ic = _lassoRotateImageCenterStart;
        final irn0 = _lassoRotateImageNormRectStart;
        if (pivot == null || startAng == null) break;
        final ang = math.atan2(local.dy - pivot.dy, local.dx - pivot.dx);
        final dRad = _unwrapAngleDelta(ang - startAng);
        final degDelta = dRad * 180 / math.pi;
        for (final s in page.strokes) {
          final b = base[s.id];
          if (b == null) continue;
          for (var i = 0; i < s.points.length && i < b.length; i++) {
            s.points[i] = _rotateDocVector(b[i] - pivot, dRad) + pivot;
          }
        }
        if (t0 != null) {
          for (final t in page.textBoxes) {
            final start = t0[t.id];
            if (start == null) continue;
            t.rotationDeg = start + degDelta;
            // Rigidly rotate the rect's center around the lasso pivot so
            // multiple text boxes orbit the group center together.
            final c0 = tc?[t.id];
            if (c0 != null) {
              final c1 = _rotateDocVector(c0 - pivot, dRad) + pivot;
              final rn = trn0?[t.id];
              final wN = rn?.width ?? t.rect.width;
              final hN = rn?.height ?? t.rect.height;
              final widthPx = wN * w;
              final heightPx = hN * h;
              final newLeftPx = c1.dx - widthPx * 0.5;
              final newTopPx = c1.dy - heightPx * 0.5;
              t.rect.left = (newLeftPx / w).clamp(0.0, 1.0 - wN);
              t.rect.top = (newTopPx / h).clamp(0.0, 1.0 - hN);
              t.rect.width = wN;
              t.rect.height = hN;
            }
          }
        }
        if (i0 != null) {
          for (final img in page.placedImages) {
            final start = i0[img.id];
            if (start == null) continue;
            img.rotationDeg = start + degDelta;
            final c0 = ic?[img.id];
            if (c0 != null) {
              final c1 = _rotateDocVector(c0 - pivot, dRad) + pivot;
              final rn = irn0?[img.id];
              final wN = rn?.width ?? img.rect.width;
              final hN = rn?.height ?? img.rect.height;
              final widthPx = wN * w;
              final heightPx = hN * h;
              final newLeftPx = c1.dx - widthPx * 0.5;
              final newTopPx = c1.dy - heightPx * 0.5;
              img.rect.left = (newLeftPx / w).clamp(0.0, 1.0 - wN);
              img.rect.top = (newTopPx / h).clamp(0.0, 1.0 - hN);
              img.rect.width = wN;
              img.rect.height = hN;
            }
          }
        }
        // Track the OBB rotation so the selection chrome tilts with content.
        // Accumulate so successive rotations continue from the current angle.
        _selRotationRad = _lassoRotateBoxStartRad + dRad;
        setState(() {});
        break;
      case _LassoDragKind.resize:
        _lassoResizeDidChange = true;
        final startAabb = _lassoResizeStartAabb;
        if (startAabb == null) break;
        final rawLocal = _documentPointFromPointer(
          event.localPosition,
          canvasSize,
        );
        final pResize = _selRotationRad.abs() > 1e-5
            ? _selectionUnrotatedPoint(rawLocal)
            : rawLocal;
        final cw = w;
        final ch = h;
        final nx0 = startAabb.left;
        final ny0 = startAabb.top;
        final nx1 = startAabb.right;
        final ny1 = startAabb.bottom;
        const minPx = 24.0;
        final mx = pResize.dx.clamp(0.0, cw);
        final my = pResize.dy.clamp(0.0, ch);
        double nL = nx0;
        double nR = nx1;
        double nT = ny0;
        double nB = ny1;
        final hi = _lassoResizeCorner;
        if (hi < 4) {
          final fixed = <Offset>[
            Offset(nx1, ny1),
            Offset(nx0, ny1),
            Offset(nx0, ny0),
            Offset(nx1, ny0),
          ][hi];
          final opposite = <Offset>[
            Offset(nx0, ny0),
            Offset(nx1, ny0),
            Offset(nx1, ny1),
            Offset(nx0, ny1),
          ][hi];
          final vx = opposite.dx - fixed.dx;
          final vy = opposite.dy - fixed.dy;
          final denom = vx * vx + vy * vy;
          final w0 = (nx1 - nx0).abs();
          final h0 = (ny1 - ny0).abs();
          final sMin = math.max(
            minPx / math.max(w0, 1e-9),
            minPx / math.max(h0, 1e-9),
          );
          var s = denom < 1e-9
              ? 1.0
              : (((mx - fixed.dx) * vx + (my - fixed.dy) * vy) / denom);
          if (s < sMin) {
            s = sMin;
          }
          final newO = Offset(fixed.dx + s * vx, fixed.dy + s * vy);
          nL = math.min(fixed.dx, newO.dx);
          nR = math.max(fixed.dx, newO.dx);
          nT = math.min(fixed.dy, newO.dy);
          nB = math.max(fixed.dy, newO.dy);
        } else {
          if (hi == 4) {
            nB = ny1;
            nT = math.min(my, ny1 - minPx);
          } else if (hi == 5) {
            nL = nx0;
            nR = math.max(mx, nx0 + minPx);
          } else if (hi == 6) {
            nT = ny0;
            nB = math.max(my, ny0 + minPx);
          } else if (hi == 7) {
            nR = nx1;
            nL = math.min(mx, nx1 - minPx);
          }
          if (nR - nL < minPx) {
            if (hi == 5) {
              nR = nL + minPx;
            } else if (hi == 7) {
              nL = nR - minPx;
            }
          }
          if (nB - nT < minPx) {
            if (hi == 4) {
              nT = nB - minPx;
            } else if (hi == 6) {
              nB = nT + minPx;
            }
          }
        }
        nL = nL.clamp(0.0, cw);
        nR = nR.clamp(0.0, cw);
        nT = nT.clamp(0.0, ch);
        nB = nB.clamp(0.0, ch);

        // Scale every selected child from the fixed (un-dragged) corner so
        // strokes, images and text move/grow together.
        final newAabb = Rect.fromLTRB(nL, nT, nR, nB);
        final sx0 = startAabb.width <= 0
            ? 1.0
            : newAabb.width / startAabb.width;
        final sy0 = startAabb.height <= 0
            ? 1.0
            : newAabb.height / startAabb.height;
        // Determine the anchor corner (the side opposite to the drag handle).
        final anchorOld = switch (hi) {
          0 => startAabb.bottomRight,
          1 => startAabb.bottomLeft,
          2 => startAabb.topLeft,
          3 => startAabb.topRight,
          4 => Offset(startAabb.center.dx, startAabb.bottom),
          5 => Offset(startAabb.left, startAabb.center.dy),
          6 => Offset(startAabb.center.dx, startAabb.top),
          7 => Offset(startAabb.right, startAabb.center.dy),
          _ => startAabb.center,
        };
        final anchorNew = switch (hi) {
          0 => newAabb.bottomRight,
          1 => newAabb.bottomLeft,
          2 => newAabb.topLeft,
          3 => newAabb.topRight,
          4 => Offset(newAabb.center.dx, newAabb.bottom),
          5 => Offset(newAabb.left, newAabb.center.dy),
          6 => Offset(newAabb.center.dx, newAabb.top),
          7 => Offset(newAabb.right, newAabb.center.dy),
          _ => newAabb.center,
        };
        // Edge handles only scale one axis; corners use uniform scale (sx≈sy).
        final sCorner = hi < 4
            ? math.min(sx0, sy0)
            : sx0; // min guards float drift
        final sx = (hi == 4 || hi == 6) ? 1.0 : (hi < 4 ? sCorner : sx0);
        final sy = (hi == 5 || hi == 7) ? 1.0 : (hi < 4 ? sCorner : sy0);

        Offset scalePt(Offset p) => Offset(
          anchorNew.dx + (p.dx - anchorOld.dx) * sx,
          anchorNew.dy + (p.dy - anchorOld.dy) * sy,
        );

        final strokeStart = _lassoResizeStrokePointsStart;
        if (strokeStart != null) {
          for (final s in page.strokes) {
            final base0 = strokeStart[s.id];
            if (base0 == null) continue;
            for (var i = 0; i < s.points.length && i < base0.length; i++) {
              s.points[i] = scalePt(base0[i]);
            }
          }
        }
        final imgStart = _lassoResizeImageNormStart;
        if (imgStart != null) {
          for (final img in page.placedImages) {
            final r0n = imgStart[img.id];
            if (r0n == null) continue;
            final r0 = r0n.toLocalRect(canvasSize);
            final tlNew = scalePt(r0.topLeft);
            final brNew = scalePt(r0.bottomRight);
            final newRect = Rect.fromPoints(tlNew, brNew);
            img.rect = _NormRect.fromLocalRect(newRect, canvasSize);
          }
        }
        final textStart = _lassoResizeTextNormStart;
        final textFontStart = _lassoResizeTextFontStart;
        if (textStart != null) {
          for (final t in page.textBoxes) {
            final r0n = textStart[t.id];
            if (r0n == null) continue;
            final r0 = r0n.toLocalRect(canvasSize);
            final tlNew = scalePt(r0.topLeft);
            final brNew = scalePt(r0.bottomRight);
            final newRect = Rect.fromPoints(tlNew, brNew);
            t.rect = _NormRect.fromLocalRect(newRect, canvasSize);
            // Scale font size to keep glyphs proportional to the box. Use the
            // smaller axis to avoid overflowing the new rect.
            final fontStart = textFontStart?[t.id];
            if (fontStart != null) {
              final fontScale = math.min(sx, sy);
              final next = (fontStart * fontScale).clamp(6.0, 200.0);
              t.fontSize = next.toDouble();
              t.markUpdated();
            }
          }
        }

        _selBaseBounds = newAabb;
        setState(() {});
        break;
    }
  }

  void _lassoPointerUp(PointerUpEvent event, Size canvasSize) {
    _endPageSwipe(event);
    if (_lassoPointerId != event.pointer) return;
    final page = _activeMemoPage;
    final endedDrag = _lassoDrag;
    final wasPendingMarquee =
        _lassoPendingMarqueePointer == event.pointer &&
        _lassoPendingMarqueeStart != null;

    // Pending one-finger touch ended without moving past the slop → treat as
    // a "tap on empty canvas" deselect. If a two-finger gesture preempted us
    // earlier the pending state was already cleared and we keep the selection.
    if (endedDrag == _LassoDragKind.idle && wasPendingMarquee && page != null) {
      if (_hasLassoSelection) {
        _clearSelection();
      }
    }

    if (endedDrag == _LassoDragKind.marquee &&
        _lassoGestureStartLocal != null &&
        page != null) {
      final end = _documentPointFromPointer(event.localPosition, canvasSize);
      _recordDebugPointer(event.localPosition, canvasSize);
      final start = _lassoGestureStartLocal!;
      var path = List<Offset>.from(_lassoPathLocal ?? [start]);
      if (path.isEmpty) {
        path.add(start);
      }
      if ((path.last - end).distance > 0.5) {
        path.add(end);
      }
      final tapMove = (end - start).distance < 5 && path.length < 3;
      if (tapMove) {
        _selectTopAt(start, canvasSize, page);
      } else {
        final closed = _prepareLassoSelectionPath(path);
        if (closed.length >= 3) {
          _applyLassoPolygonSelection(closed, canvasSize, page);
        }
      }
    }

    if (page != null) {
      if (endedDrag == _LassoDragKind.move &&
          _lassoMoveDidChange &&
          _pendingMoveUndo != null) {
        page.pushLayoutUndo(_pendingMoveUndo!);
      }
      if (endedDrag == _LassoDragKind.resize &&
          _lassoResizeDidChange &&
          _pendingResizeUndo != null) {
        page.pushLayoutUndo(_pendingResizeUndo!);
      }
      if (endedDrag == _LassoDragKind.rotate &&
          _lassoRotateDidChange &&
          _pendingRotateUndo != null) {
        page.pushLayoutUndo(_pendingRotateUndo!);
      }
    }

    // After rotate / move / resize the OBB (`_selBaseBounds` +
    // `_selRotationRad`) already tracks the new geometry — no reset needed.
    // The OBB only needs a fresh fit when the membership of the selection
    // changes (lasso polygon, paste, etc.).

    final shouldPersist =
        endedDrag == _LassoDragKind.move ||
        endedDrag == _LassoDragKind.resize ||
        endedDrag == _LassoDragKind.rotate ||
        endedDrag == _LassoDragKind.marquee;

    _lassoPointerId = null;
    _lassoDrag = _LassoDragKind.idle;
    _lassoPathLocal = null;
    _lassoGestureStartLocal = null;
    _lassoMoveAnchorLocal = null;
    _lassoMoveStrokePointsStart = null;
    _lassoMoveImageNormStart = null;
    _lassoMoveTextNormStart = null;
    _lassoResizeStartAabb = null;
    _lassoResizeStrokePointsStart = null;
    _lassoResizeImageNormStart = null;
    _lassoResizeTextNormStart = null;
    _lassoResizeTextFontStart = null;
    _lassoMoveDidChange = false;
    _lassoResizeDidChange = false;
    _lassoRotateDidChange = false;
    _lassoRotatePivot = null;
    _lassoRotatePointerStartAngle = null;
    _lassoRotateStrokeBaseline = null;
    _lassoRotateTextStartDeg = null;
    _lassoRotateImageStartDeg = null;
    _lassoRotateTextCenterStart = null;
    _lassoRotateImageCenterStart = null;
    _lassoRotateTextNormRectStart = null;
    _lassoRotateImageNormRectStart = null;
    _lassoPendingMarqueePointer = null;
    _lassoPendingMarqueeStart = null;
    _pendingMoveUndo = null;
    _pendingResizeUndo = null;
    _pendingRotateUndo = null;
    setState(() {});
    if (shouldPersist) {
      _markDirty();
    }
  }

  void _lassoPointerCancel(PointerCancelEvent event) {
    _endPageSwipe(event);
    if (_lassoPointerId != event.pointer) return;
    _lassoPointerId = null;
    _lassoDrag = _LassoDragKind.idle;
    _lassoPathLocal = null;
    _lassoGestureStartLocal = null;
    _lassoMoveAnchorLocal = null;
    _lassoMoveStrokePointsStart = null;
    _lassoMoveImageNormStart = null;
    _lassoMoveTextNormStart = null;
    _lassoResizeStartAabb = null;
    _lassoResizeStrokePointsStart = null;
    _lassoResizeImageNormStart = null;
    _lassoResizeTextNormStart = null;
    _lassoResizeTextFontStart = null;
    _lassoMoveDidChange = false;
    _lassoResizeDidChange = false;
    _lassoRotateDidChange = false;
    _lassoRotatePivot = null;
    _lassoRotatePointerStartAngle = null;
    _lassoRotateStrokeBaseline = null;
    _lassoRotateTextStartDeg = null;
    _lassoRotateImageStartDeg = null;
    _lassoRotateTextCenterStart = null;
    _lassoRotateImageCenterStart = null;
    _lassoRotateTextNormRectStart = null;
    _lassoRotateImageNormRectStart = null;
    _lassoPendingMarqueePointer = null;
    _lassoPendingMarqueeStart = null;
    _pendingMoveUndo = null;
    _pendingResizeUndo = null;
    _pendingRotateUndo = null;
    setState(() {});
  }

  // ── Text tool (Aa) ───────────────────────────────────────────

  _CanvasTextBox? _textBoxById(String id) {
    final page = _activeMemoPage;
    if (page == null) return null;
    for (final t in page.textBoxes) {
      if (t.id == id) return t;
    }
    return null;
  }

  static const double _kTextMinW = 48;
  static const double _kTextMinH = 28;

  void _applyCanvasTextMoveByDelta(String id, Offset deltaPx, Size canvasSize) {
    final t = _textBoxById(id);
    if (t == null) return;
    if (id == _pendingCanvasTextDragId &&
        _pendingCanvasTextDragUndo != null &&
        (deltaPx.dx.abs() > 0.08 || deltaPx.dy.abs() > 0.08)) {
      _canvasTextDragDidChange = true;
    }
    final r = t.rect.toLocalRect(canvasSize).shift(deltaPx);
    final shifted = Rect.fromLTWH(
      r.left.clamp(0, math.max(0.0, canvasSize.width - r.width)),
      r.top.clamp(0, math.max(0.0, canvasSize.height - r.height)),
      r.width,
      r.height,
    );
    setState(() {
      t.rect = _NormRect.fromLocalRect(shifted, canvasSize);
      t.markUpdated();
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _beginCanvasTextDragUndo(String textId) {
    final page = _activeMemoPage;
    if (page == null) return;
    final t = _textBoxById(textId);
    if (t == null) return;
    _pendingCanvasTextDragUndo = _LassoLayoutSnapshot(
      strokePoints: {},
      imageRects: {},
      textRects: {textId: t.rect.copy()},
      textBodies: {textId: t.text},
      textRotationDeg: {textId: t.rotationDeg},
    );
    _pendingCanvasTextDragId = textId;
    _canvasTextDragDidChange = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _endCanvasTextDragUndo() {
    final page = _activeMemoPage;
    if (page != null &&
        _canvasTextDragDidChange &&
        _pendingCanvasTextDragUndo != null) {
      page.pushLayoutUndo(_pendingCanvasTextDragUndo!);
      _markDirty();
    }
    _pendingCanvasTextDragUndo = null;
    _pendingCanvasTextDragId = null;
    _canvasTextDragDidChange = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _beginCanvasTextResizeUndo(String textId) {
    final page = _activeMemoPage;
    final t = _textBoxById(textId);
    if (page == null || t == null) return;
    _pendingCanvasTextResizeUndo = _LassoLayoutSnapshot(
      strokePoints: {},
      imageRects: {},
      textRects: {textId: t.rect.copy()},
      textBodies: {textId: t.text},
      textRotationDeg: {textId: t.rotationDeg},
    );
    _pendingCanvasTextResizeId = textId;
    _canvasTextResizeChanged = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _endCanvasTextResizeUndo() {
    final page = _activeMemoPage;
    if (page != null &&
        _canvasTextResizeChanged &&
        _pendingCanvasTextResizeUndo != null) {
      page.pushLayoutUndo(_pendingCanvasTextResizeUndo!);
      _markDirty();
    }
    _pendingCanvasTextResizeUndo = null;
    _pendingCanvasTextResizeId = null;
    _canvasTextResizeChanged = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _beginCanvasTextRotateUndo(String textId) {
    final page = _activeMemoPage;
    final t = _textBoxById(textId);
    if (page == null || t == null) return;
    _pendingCanvasTextRotateUndo = _LassoLayoutSnapshot(
      strokePoints: {},
      imageRects: {},
      textRects: {textId: t.rect.copy()},
      textBodies: {textId: t.text},
      textRotationDeg: {textId: t.rotationDeg},
    );
    _pendingCanvasTextRotateId = textId;
    _canvasTextRotateChanged = false;
    _syncInteractiveViewerGestureAvailability();
  }

  void _setCanvasTextRotationWhileDragging(String textId, double deg) {
    final t = _textBoxById(textId);
    if (t == null || textId != _pendingCanvasTextRotateId) return;
    if ((deg - t.rotationDeg).abs() > 1e-4) {
      _canvasTextRotateChanged = true;
    }
    setState(() {
      t.rotationDeg = deg;
      t.markUpdated();
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _endCanvasTextRotateUndo() {
    final page = _activeMemoPage;
    if (page != null &&
        _canvasTextRotateChanged &&
        _pendingCanvasTextRotateUndo != null) {
      page.pushLayoutUndo(_pendingCanvasTextRotateUndo!);
      _markDirty();
    }
    _pendingCanvasTextRotateUndo = null;
    _pendingCanvasTextRotateId = null;
    _canvasTextRotateChanged = false;
    _syncInteractiveViewerGestureAvailability();
  }

  Rect? _boundsUnionForTextIds(
    Set<String> ids,
    Size canvasSize,
    _CanvasPage page,
  ) {
    Rect? u;
    for (final t in page.textBoxes) {
      if (!ids.contains(t.id)) continue;
      final r = t.rect.toLocalRect(canvasSize);
      u = u == null ? r : u.expandToInclude(r);
    }
    return u;
  }

  Future<void> _textDuplicateSelectionNearby(Size canvasSize) async {
    final page = _activeMemoPage;
    if (page == null || _tool != _ToolType.text) return;
    if (_selectedTextIds.isEmpty) return;
    final b = _boundsUnionForTextIds(_selectedTextIds, canvasSize, page);
    if (b == null) return;
    _captureStudioClipboard(page, b.center);
    await _duplicateLassoSelectionByDelta(
      page,
      const Offset(14, 14),
      canvasSize,
    );
  }

  void _textToolbarDeleteSelection() {
    if (_tool != _ToolType.text || _selectedTextIds.isEmpty) return;
    _deleteSelectedObjects();
  }

  /// True when text-toolbar actions should touch on-canvas boxes (not only defaults).
  bool _textToolbarAffectsPlacedTextBoxes() {
    return _tool == _ToolType.text &&
        (_textEditingId != null || _selectedTextIds.isNotEmpty);
  }

  void _forEachToolbarTextBox(void Function(_CanvasTextBox t) fn) {
    final page = _activeMemoPage;
    if (page == null || _tool != _ToolType.text) return;
    for (final t in page.textBoxes) {
      final id = t.id;
      final inScope =
          (_textEditingId != null && id == _textEditingId) ||
          _selectedTextIds.contains(id);
      if (inScope) fn(t);
    }
  }

  void _pushFullTextLayoutUndo() {
    final page = _activeMemoPage;
    if (page == null || !_textToolbarAffectsPlacedTextBoxes()) return;
    page.pushLayoutUndo(
      _LassoLayoutSnapshot(
        strokePoints: {},
        imageRects: {},
        textRects: {},
        textBodies: {},
        fullTextBoxesJson: page.textBoxes
            .map((x) => x.toJson(emitPageId: page.id))
            .toList(),
      ),
    );
  }

  void _pruneStaleSelections() {
    final page = _activeMemoPage;
    if (page == null) return;
    final sIds = page.strokes.map((s) => s.id).toSet();
    final iIds = page.placedImages.map((e) => e.id).toSet();
    final tIds = page.textBoxes.map((t) => t.id).toSet();
    final beforeS = _selectedStrokeIds.length;
    final beforeI = _selectedImageIds.length;
    final beforeT = _selectedTextIds.length;
    _selectedStrokeIds.removeWhere((id) => !sIds.contains(id));
    _selectedImageIds.removeWhere((id) => !iIds.contains(id));
    _selectedTextIds.removeWhere((id) => !tIds.contains(id));
    final hasAny =
        _selectedStrokeIds.isNotEmpty ||
        _selectedImageIds.isNotEmpty ||
        _selectedTextIds.isNotEmpty;
    if (!hasAny) {
      _selBaseBounds = null;
      _selRotationRad = 0;
    } else if (beforeS != _selectedStrokeIds.length ||
        beforeI != _selectedImageIds.length ||
        beforeT != _selectedTextIds.length) {
      // Selection shrank; drop the cached OBB so the next paint recomputes a
      // tight AABB from the still-selected content.
      _selBaseBounds = null;
      _selRotationRad = 0;
    }
  }

  void _applyCanvasTextResizeHandle(
    String id,
    int handle,
    Offset d,
    Size canvasSize,
  ) {
    final t = _textBoxById(id);
    if (t == null) return;
    if (id == _pendingCanvasTextResizeId &&
        _pendingCanvasTextResizeUndo != null &&
        (d.dx.abs() > 0.02 || d.dy.abs() > 0.02)) {
      _canvasTextResizeChanged = true;
    }
    // Once the user grabs a handle, future typing must respect the
    // user-chosen width (no auto-grow horizontally). Heights still grow
    // because `_autoFitTextBox` enforces a measured min.
    t.autoSize = false;

    var r = t.rect.toLocalRect(canvasSize);
    // Dynamic minimum: the actual rendered text must never be clipped.
    // Width: measure unconstrained (real glyph width).
    // Height: measure with the *new* inner width so wrapped lines fit.
    final unconstrained = _measureTextBoxContentPx(t);
    final minWBase =
        unconstrained.width + _kTextInlineHorizontalPadding * 2 + 8;
    final minW = math.max(_kTextMinW, minWBase);
    // Determine the candidate inner width given the dragged handle so the
    // height clamp uses the same width the user is trying to apply.
    double previewWidth = r.width;
    if (handle == 0 || handle == 6 || handle == 7) {
      previewWidth = r.width - d.dx;
    } else if (handle == 2 || handle == 3 || handle == 4) {
      previewWidth = r.width + d.dx;
    }
    if (previewWidth < minW) previewWidth = minW;
    final wrapped = _measureTextBoxContentPx(
      t,
      maxWidth: math.max(1.0, previewWidth - _kTextInlineHorizontalPadding * 2),
    );
    final minH = math.max(
      _kTextMinH,
      wrapped.height + _kTextInlineVerticalPadding * 2 + 6,
    );

    if (handle == 0) {
      r = Rect.fromLTRB(
        (r.left + d.dx).clamp(0, r.right - minW),
        (r.top + d.dy).clamp(0, r.bottom - minH),
        r.right,
        r.bottom,
      );
    } else if (handle == 1) {
      r = Rect.fromLTRB(
        r.left,
        (r.top + d.dy).clamp(0, r.bottom - minH),
        r.right,
        r.bottom,
      );
    } else if (handle == 2) {
      r = Rect.fromLTRB(
        r.left,
        (r.top + d.dy).clamp(0, r.bottom - minH),
        (r.right + d.dx).clamp(r.left + minW, canvasSize.width),
        r.bottom,
      );
    } else if (handle == 3) {
      r = Rect.fromLTRB(
        r.left,
        r.top,
        (r.right + d.dx).clamp(r.left + minW, canvasSize.width),
        r.bottom,
      );
    } else if (handle == 4) {
      r = Rect.fromLTRB(
        r.left,
        r.top,
        (r.right + d.dx).clamp(r.left + minW, canvasSize.width),
        (r.bottom + d.dy).clamp(r.top + minH, canvasSize.height),
      );
    } else if (handle == 5) {
      r = Rect.fromLTRB(
        r.left,
        r.top,
        r.right,
        (r.bottom + d.dy).clamp(r.top + minH, canvasSize.height),
      );
    } else if (handle == 6) {
      r = Rect.fromLTRB(
        (r.left + d.dx).clamp(0, r.right - minW),
        r.top,
        r.right,
        (r.bottom + d.dy).clamp(r.top + minH, canvasSize.height),
      );
    } else if (handle == 7) {
      r = Rect.fromLTRB(
        (r.left + d.dx).clamp(0, r.right - minW),
        r.top,
        r.right,
        r.bottom,
      );
    } else {
      return;
    }
    setState(() {
      t.rect = _NormRect.fromLocalRect(r, canvasSize);
      t.markUpdated();
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _selectCanvasTextSingle(String id) {
    if (_tool != _ToolType.text) return;
    _finishInlineTextEdit(notify: false);
    setState(() {
      _selectedTextIds
        ..clear()
        ..add(id);
    });
    _textLayerRepaint.value++;
  }

  void _onTextEditControllerChanged() {
    if (!mounted) return;
    final id = _textEditingId;
    final c = _textEditController;
    final page = _activeMemoPage;
    if (id == null || c == null || page == null) return;
    for (final t in page.textBoxes) {
      if (t.id == id) {
        if (t.text != c.text) {
          t.text = c.text;
          t.markUpdated();
          _autoFitTextBox(t);
        }
        break;
      }
    }
    _textLayerRepaint.value++;
  }

  /// Measure the raw rendered px size of [box.text] using the box's own
  /// typography. Returns a [Size] in canvas-local px (no padding included).
  /// When [maxWidth] is omitted, the text is laid out unconstrained which
  /// gives the natural single-line width for short content.
  Size _measureTextBoxContentPx(_CanvasTextBox box, {double? maxWidth}) {
    final style = _canvasTextBoxTextStyle(box);
    final tp = TextPainter(
      text: TextSpan(text: box.text.isEmpty ? ' ' : box.text, style: style),
      strutStyle: _canvasTextBoxStrutStyle(box),
      textDirection: TextDirection.ltr,
      maxLines: null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return Size(tp.width, tp.height);
  }

  /// Smallest outer [Size] the text box may shrink to without clipping or
  /// dropping descenders. Includes inline padding plus a small safety margin
  /// so Korean 받침/g·j 등 descender glyphs never get cut off.
  ///
  /// [maxInnerWidth] caps the layout width when the user has already
  /// resized the box narrower than the text would naturally take — in that
  /// case we measure with wrapping enabled so the min size reflects the
  /// wrapped height.
  Size _textBoxMinOuterSize(_CanvasTextBox box, {double? maxInnerWidth}) {
    final m = _measureTextBoxContentPx(box, maxWidth: maxInnerWidth);
    final w = m.width + _kTextInlineHorizontalPadding * 2 + 8;
    final h = m.height + _kTextInlineVerticalPadding * 2 + 6;
    return Size(math.max(_kTextMinW, w), math.max(_kTextMinH, h));
  }

  /// Grow [box] so its rect matches the current text content.
  ///
  /// In `autoSize == true` mode (Goodnotes-style): width and height both
  /// follow typed text. Width is capped at the remaining canvas width so
  /// long single lines wrap naturally rather than overflowing the page.
  ///
  /// In `autoSize == false` mode (user has resized manually): width stays
  /// at whatever the user chose; only height grows when content wraps, and
  /// the box never shrinks below the measured min height (so descenders /
  /// extra lines never get clipped).
  void _autoFitTextBox(_CanvasTextBox box) {
    final canvas = _pointerCanvasSize;
    if (canvas == null || canvas.width <= 0 || canvas.height <= 0) return;
    final r = box.rect.toLocalRect(canvas);
    final padW = _kTextInlineHorizontalPadding * 2 + 8;
    final padH = _kTextInlineVerticalPadding * 2 + 6;

    if (box.autoSize) {
      // Unconstrained width gives the natural single-line width.
      final natural = _measureTextBoxContentPx(box);
      final maxOuterW = math.max(_kTextMinW, canvas.width - r.left - 4);
      var outerW = natural.width + padW;
      if (outerW > maxOuterW) outerW = maxOuterW;
      if (outerW < _kTextMinW) outerW = _kTextMinW;
      final innerW = math.max(1.0, outerW - padW);
      final wrapped = _measureTextBoxContentPx(box, maxWidth: innerW);
      var outerH = wrapped.height + padH;
      if (outerH < _kTextMinH) outerH = _kTextMinH;
      final maxOuterH = math.max(_kTextMinH, canvas.height - r.top - 2);
      if (outerH > maxOuterH) outerH = maxOuterH;
      final nw = (outerW / canvas.width).clamp(0.0, 1.0);
      final nh = (outerH / canvas.height).clamp(0.0, 1.0);
      final changed =
          (nw - box.rect.width).abs() > 1e-4 ||
          (nh - box.rect.height).abs() > 1e-4;
      box.rect.width = nw;
      box.rect.height = nh;
      if (changed) box.markUpdated();
      return;
    }

    // Manual-size mode: only height follows content. The min height comes
    // from measured wrapped content so the user can never shrink below it.
    final innerW = math.max(1.0, r.width - _kTextInlineHorizontalPadding * 2);
    final wrapped = _measureTextBoxContentPx(box, maxWidth: innerW);
    final desiredPx = wrapped.height + padH;
    final minOuterH = _textBoxMinOuterSize(box, maxInnerWidth: innerW).height;
    final clampedPx = math.max(minOuterH, desiredPx);
    final maxAvail = math.max(minOuterH, canvas.height - r.top - 2);
    final newH = math.min(clampedPx, maxAvail);
    if ((newH - r.height).abs() < 0.5) return;
    box.rect.height = (newH / canvas.height).clamp(0.0, 1.0);
    box.markUpdated();
  }

  void _finishInlineTextEdit({bool notify = true}) {
    final id = _textEditingId;
    final hadInlineSession = id != null;
    final c = _textEditController;
    final page = _activeMemoPage;
    if (id != null && c != null && page != null) {
      for (final t in page.textBoxes) {
        if (t.id == id) {
          t.text = c.text;
          t.markUpdated();
          break;
        }
      }
    }
    if (id != null && page != null && _inlineTextEditUndoBaseline != null) {
      var edited = '';
      for (final t in page.textBoxes) {
        if (t.id == id) {
          edited = t.text;
          break;
        }
      }
      var baseline = '';
      for (final m in _inlineTextEditUndoBaseline!) {
        if (m['id'] == id) {
          baseline = m['text'] as String? ?? '';
          break;
        }
      }
      if (baseline != edited) {
        page.pushLayoutUndo(
          _LassoLayoutSnapshot(
            strokePoints: {},
            imageRects: {},
            textRects: {},
            textBodies: {},
            fullTextBoxesJson: List<Map<String, dynamic>>.from(
              _inlineTextEditUndoBaseline!,
            ),
          ),
        );
      }
    }
    _inlineTextEditUndoBaseline = null;
    _textEditController?.removeListener(_onTextEditControllerChanged);
    _textEditController?.dispose();
    _textEditController = null;
    _textEditingId = null;
    _textLayerRepaint.value++;
    if (notify) {
      _markDirty();
    }
    if (hadInlineSession) {
      _syncInteractiveViewerGestureAvailability();
    }
  }

  void _beginInlineTextEdit(_CanvasTextBox box) {
    _finishInlineTextEdit(notify: false);
    _textEditingId = box.id;
    _textEditController = TextEditingController(text: box.text);
    _textEditController!.addListener(_onTextEditControllerChanged);
    final page = _activeMemoPage;
    if (page != null) {
      _inlineTextEditUndoBaseline = page.textBoxes
          .map((x) => x.toJson(emitPageId: page.id))
          .toList();
    } else {
      _inlineTextEditUndoBaseline = null;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFieldFocus.requestFocus();
      }
    });
  }

  void _textToolPointerDown(PointerDownEvent event, Size canvasSize) {
    _pointerCanvasSize = canvasSize;
    _beginPageSwipe(event);
    if (_isPageSwipeActive) return;
    if (!_isDrawingEnabled(event)) return;
    final page = _activeMemoPage;
    if (page == null) return;
    if (_textToolActivePointer != null) return;

    final doc = _documentPointFromPointer(event.localPosition, canvasSize);
    _recordDebugPointer(event.localPosition, canvasSize);
    // Text objects are painted above this listener and receive their own hits.
    _textToolPointerDownLocal = doc;
    _textToolActivePointer = event.pointer;
    _syncInteractiveViewerGestureAvailability();
  }

  void _textToolPointerMove(PointerMoveEvent event, Size canvasSize) {
    _maybeCancelLongPressFromMove(event.localPosition, canvasSize);
    _updatePageSwipe(event);
    if (_textToolActivePointer != event.pointer) return;
    _recordDebugPointer(event.localPosition, canvasSize);
  }

  void _textToolPointerUp(PointerUpEvent event, Size canvasSize) {
    _endPageSwipe(event);
    if (_textToolActivePointer != event.pointer) return;
    _textToolActivePointer = null;
    final page = _activeMemoPage;
    final start = _textToolPointerDownLocal;
    _textToolPointerDownLocal = null;
    _syncInteractiveViewerGestureAvailability();
    if (page == null || start == null) return;

    final rawEnd = event.localPosition;
    final endDoc = _documentPointFromPointer(rawEnd, canvasSize);
    _recordDebugPointer(rawEnd, canvasSize);
    if ((endDoc - start).distance >= 10) return;

    if (_hitTestTopTextId(start, canvasSize, page, respectLassoFilter: false) !=
        null) {
      return;
    }

    final editId = _textEditingId;
    if (editId != null) {
      final editBox = _textBoxById(editId);
      if (editBox != null) {
        final body = editBox.rect.toLocalRect(canvasSize);
        if (!body.contains(endDoc) && !body.contains(start)) {
          _finishInlineTextEdit();
        }
        return;
      }
    }

    if (_selectedTextIds.isNotEmpty ||
        _selectedStrokeIds.isNotEmpty ||
        _selectedImageIds.isNotEmpty) {
      setState(_clearSelection);
      _textLayerRepaint.value++;
      return;
    }

    final clamped = _clampToCanvas(start, canvasSize);
    final newId = _addTextBoxAtCanvasPoint(clamped, canvasSize, page);
    final box = _textBoxById(newId);
    if (box != null) {
      _beginInlineTextEdit(box);
    }
  }

  void _textToolPointerCancel(PointerCancelEvent event) {
    _endPageSwipe(event);
    if (_textToolActivePointer != event.pointer) return;
    _textToolActivePointer = null;
    _textToolPointerDownLocal = null;
    _syncInteractiveViewerGestureAvailability();
  }

  // ── Drawing ──────────────────────────────────────────────────

  void _setTool(_ToolType tool) {
    final nextTool = tool == _ToolType.hand ? _ToolType.pen : tool;
    if (nextTool == _ToolType.lasso && _tool == _ToolType.lasso) {
      _showLassoTargetFilterSheet();
      return;
    }
    if (nextTool == _ToolType.laser && _tool == _ToolType.laser) {
      setState(() {
        final s = _settingsFor(_ToolType.laser);
        s.laserModeIndex = 1 - s.laserModeIndex.clamp(0, 1);
        _clearLaserOverlay();
      });
      _markDirty();
      return;
    }
    final didChangeTool = _tool != nextTool;
    final preserveTextIds =
        didChangeTool &&
            nextTool == _ToolType.text &&
            _tool == _ToolType.lasso &&
            _selectedTextIds.length == 1 &&
            _selectedStrokeIds.isEmpty &&
            _selectedImageIds.isEmpty
        ? Set<String>.from(_selectedTextIds)
        : const <String>{};
    final hadDock = _dockTool != null && _dockPanelKind != null;
    if (didChangeTool) {
      _abortCanvasListenerPointerGesture(
        commitStrokeEraserIfChanged:
            _tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke,
      );
    }
    setState(() {
      if (didChangeTool) {
        final previousTool = _tool;
        _clearLaserOverlay();
        if (nextTool != _ToolType.text) {
          _finishInlineTextEdit(notify: false);
        }
        _tool = nextTool;
        if (nextTool == _ToolType.laser) {
          _laserDiag(
            '_setTool: active _tool is now laser (was $previousTool); '
            'transient trail cleared',
          );
        }
        if (nextTool == _ToolType.text) {
          _textStyleColorTarget = _TextStyleColorTarget.text;
          _textAuxiliaryBarHidden = false;
        }
        if (nextTool == _ToolType.lasso) {
          _dockTool = null;
          _dockPanelKind = null;
        } else if (hadDock) {
          _dockTool = nextTool;
          // 텍스트 도구에는 상단 두께 패널이 없음 — 펜 등에서 너비 패널을 연 채
          // 전환하면 빈 줄만 남으므로 닫는다. 색상 패널은 그대로 유지.
          if (nextTool == _ToolType.text &&
              _dockPanelKind == _ToolDockPanelKind.width) {
            _dockTool = null;
            _dockPanelKind = null;
          }
        } else {
          _dockTool = null;
          _dockPanelKind = null;
        }
        _clearLassoInteraction();
        if (preserveTextIds.isEmpty) {
          _clearSelection();
        } else {
          _selectedStrokeIds.clear();
          _selectedImageIds.clear();
          _selectedTextIds
            ..clear()
            ..addAll(preserveTextIds);
        }
      } else {
        if (_dockTool == _tool && _dockPanelKind != null) {
          _dockTool = null;
          _dockPanelKind = null;
        }
      }
    });
    if (didChangeTool) {
      _markDirty();
    }
  }

  void _openToolWidthPanel() {
    if (_tool == _ToolType.hand || _tool == _ToolType.lasso) return;
    if (_tool == _ToolType.text) return;
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      return;
    }
    setState(() {
      _dockTool = _tool;
      _dockPanelKind = _ToolDockPanelKind.width;
    });
  }

  void _openToolColorPanel() {
    if (_tool == _ToolType.hand || _tool == _ToolType.eraser) return;
    if (_tool == _ToolType.lasso && _selectedTextIds.isEmpty) return;
    setState(() {
      _dockTool = _tool;
      _dockPanelKind = _ToolDockPanelKind.color;
      if (_tool == _ToolType.text &&
          _textStyleColorTarget == _TextStyleColorTarget.fill) {
        final ts = _settingsFor(_ToolType.text);
        final tgt = _primaryTextToolbarTarget();
        final c = tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor;
        _colorPanelFillAlpha = c.a / 255.0;
      } else {
        _colorPanelFillAlpha = null;
      }
    });
  }

  void _updateActiveToolWidth(double width) {
    setState(() {
      final w = _tool == _ToolType.laser ? width.clamp(3.0, 8.0) : width;
      _activeToolSettings.width = w;
      if (_tool == _ToolType.text) {
        final clipped = width.clamp(8.0, 72.0);
        if (_textToolbarAffectsPlacedTextBoxes()) {
          _forEachToolbarTextBox((tg) {
            tg.fontSize = clipped;
            tg.markUpdated();
          });
        }
      }
    });
    if (_tool == _ToolType.text) {
      _textLayerRepaint.value++;
    }
    _markDirty();
  }

  void _finishToolWidthAdjustment(double width) {
    if (_tool == _ToolType.text) {
      _pushFullTextLayoutUndo();
    }
    _updateActiveToolWidth(width);
  }

  void _updateActiveToolColor(Color color) {
    if (_tool == _ToolType.hand || _tool == _ToolType.eraser) return;
    if (_tool == _ToolType.text) {
      final ts = _settingsFor(_ToolType.text);
      final tgt = _primaryTextToolbarTarget();
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _pushFullTextLayoutUndo();
      }
      setState(() {
        switch (_textStyleColorTarget) {
          case _TextStyleColorTarget.text:
            ts.color = color;
            if (_textToolbarAffectsPlacedTextBoxes()) {
              _forEachToolbarTextBox((t) {
                t.color = color;
                t.markUpdated();
              });
            }
            break;
          case _TextStyleColorTarget.fill:
            final a = _colorPanelFillAlpha;
            final merged = color.withValues(alpha: a ?? color.a / 255.0);
            if (_textToolbarAffectsPlacedTextBoxes()) {
              _forEachToolbarTextBox((t) {
                t.backgroundColor = merged;
                t.hasBackground = true;
                t.markUpdated();
              });
            } else if (tgt != null) {
              tgt.backgroundColor = merged;
              tgt.hasBackground = true;
            } else {
              ts.textBoxNextBackgroundColor = merged;
              ts.textBoxNextHasBackground = true;
            }
            _colorPanelFillAlpha = merged.a / 255.0;
            break;
          case _TextStyleColorTarget.border:
            if (_textToolbarAffectsPlacedTextBoxes()) {
              _forEachToolbarTextBox((t) {
                t.borderColor = color;
                t.hasBorder = true;
                t.markUpdated();
              });
            } else if (tgt != null) {
              tgt.borderColor = color;
              tgt.hasBorder = true;
            } else {
              ts.textBoxNextBorderColor = color;
              ts.textBoxNextHasBorder = true;
            }
            break;
        }
        _rememberRecentColor(color);
      });
      _textLayerRepaint.value++;
      _markDirty();
      return;
    }
    if (_tool == _ToolType.lasso) {
      if (_selectedTextIds.isEmpty) return;
      final page = _activeMemoPage;
      if (page == null) return;
      page.pushLayoutUndo(
        _LassoLayoutSnapshot(
          strokePoints: {},
          imageRects: {},
          textRects: {},
          textBodies: {},
          fullTextBoxesJson: page.textBoxes
              .map((x) => x.toJson(emitPageId: page.id))
              .toList(),
        ),
      );
      setState(() {
        for (final t in page.textBoxes) {
          if (_selectedTextIds.contains(t.id)) t.color = color;
        }
        _rememberRecentColor(color);
      });
      _markDirty();
      return;
    }
    setState(() {
      _activeToolSettings.color = color;
      _rememberRecentColor(color);
    });
    _markDirty();
  }

  void _rememberRecentColor(Color color) {
    final next = _recentColors
        .where((entry) => entry.toARGB32() != color.toARGB32())
        .toList();
    _recentColors = [color, ...next].take(5).toList();
  }

  void _updateActiveToolOpacity(double opacity) {
    if (_tool == _ToolType.hand ||
        _tool == _ToolType.eraser ||
        _tool == _ToolType.lasso ||
        _tool == _ToolType.text) {
      return;
    }
    setState(() {
      _activeToolSettings.opacity = opacity;
    });
    _markDirty();
  }

  void _finishToolOpacityAdjustment(double opacity) {
    _updateActiveToolOpacity(opacity);
  }

  Future<void> _openAdvancedColorPicker({required bool editOpacity}) async {
    if (_tool == _ToolType.hand || _tool == _ToolType.eraser) return;
    if (_tool == _ToolType.lasso && _selectedTextIds.isEmpty) return;

    var initialColor = _activeColor;
    var initialOpacity = _activeOpacity;
    var effectiveEditOpacity = editOpacity;
    if (_tool == _ToolType.text) {
      final tgt = _primaryTextToolbarTarget();
      final ts = _settingsFor(_ToolType.text);
      initialColor = switch (_textStyleColorTarget) {
        _TextStyleColorTarget.text => tgt?.color ?? ts.color,
        _TextStyleColorTarget.fill =>
          tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor,
        _TextStyleColorTarget.border =>
          tgt?.borderColor ?? ts.textBoxNextBorderColor,
      };
      if (_textStyleColorTarget == _TextStyleColorTarget.fill) {
        initialOpacity = initialColor.a / 255.0;
        effectiveEditOpacity = true;
      } else {
        initialOpacity = 1;
        effectiveEditOpacity = false;
      }
    }
    if (_tool == _ToolType.lasso) {
      final page = _activeMemoPage;
      if (page != null) {
        for (final t in page.textBoxes) {
          if (_selectedTextIds.contains(t.id)) {
            initialColor = t.color;
            break;
          }
        }
      }
      initialOpacity = 1;
      effectiveEditOpacity = false;
    }

    final selected = await showDialog<_AdvancedColorResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _AdvancedColorDialog(
        initialColor: initialColor,
        initialOpacity: initialOpacity,
        editOpacity: effectiveEditOpacity,
      ),
    );

    if (selected != null) {
      if (_tool == _ToolType.text &&
          _textStyleColorTarget == _TextStyleColorTarget.fill &&
          effectiveEditOpacity) {
        _pushFullTextLayoutUndo();
        setState(() {
          final merged = selected.color.withValues(alpha: selected.opacity);
          final ts = _settingsFor(_ToolType.text);
          if (_textToolbarAffectsPlacedTextBoxes()) {
            _forEachToolbarTextBox((t) {
              t.backgroundColor = merged;
              t.hasBackground = true;
              t.markUpdated();
            });
          } else {
            final tgt = _primaryTextToolbarTarget();
            if (tgt != null) {
              tgt.backgroundColor = merged;
              tgt.hasBackground = true;
            } else {
              ts.textBoxNextBackgroundColor = merged;
              ts.textBoxNextHasBackground = true;
            }
          }
          _colorPanelFillAlpha = selected.opacity;
          _rememberRecentColor(selected.color);
        });
        _textLayerRepaint.value++;
        _markDirty();
        return;
      }
      _updateActiveToolColor(selected.color);
      if (effectiveEditOpacity) {
        _updateActiveToolOpacity(selected.opacity);
      }
    }
  }

  Future<void> _promptWidthNumeric(BuildContext panelContext) async {
    if (_tool == _ToolType.text) {
      final ctrl = TextEditingController(text: _activeWidth.round().toString());
      final v = await showDialog<double>(
        context: panelContext,
        builder: (ctx) => AlertDialog(
          title: const Text('글자 크기'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '8 ~ 72',
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
                final parsed = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim(),
                );
                if (parsed == null) return;
                Navigator.pop(ctx, parsed.clamp(8.0, 72.0));
              },
              child: const Text('적용'),
            ),
          ],
        ),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose),
      );
      if (v != null) _finishToolWidthAdjustment(v);
      return;
    }

    if (_tool == _ToolType.laser) {
      final ctrl = TextEditingController(text: _activeWidth.toStringAsFixed(1));
      final v = await showDialog<double>(
        context: panelContext,
        builder: (ctx) => AlertDialog(
          title: const Text('레이저 두께 입력'),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '3.0 ~ 8.0',
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
                final parsed = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim(),
                );
                if (parsed == null) return;
                Navigator.pop(ctx, parsed.clamp(3.0, 8.0));
              },
              child: const Text('적용'),
            ),
          ],
        ),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose),
      );
      if (v != null) _finishToolWidthAdjustment(v);
      return;
    }

    final ctrl = TextEditingController(text: _activeWidth.toStringAsFixed(1));
    final v = await showDialog<double>(
      context: panelContext,
      builder: (ctx) => AlertDialog(
        title: const Text('두께 입력'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '1.0 ~ 14.0',
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
              final parsed = double.tryParse(
                ctrl.text.replaceAll(',', '.').trim(),
              );
              if (parsed == null) return;
              Navigator.pop(ctx, parsed.clamp(1.0, 14.0));
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose),
    );
    if (v != null) _finishToolWidthAdjustment(v);
  }

  Future<void> _promptOpacityPercentNumeric(BuildContext panelContext) async {
    final pct = (_activeOpacity * 100).round().clamp(5, 100);
    final ctrl = TextEditingController(text: '$pct');
    final v = await showDialog<int>(
      context: panelContext,
      builder: (ctx) => AlertDialog(
        title: const Text('투명도 (%)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '5 ~ 100',
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
              final parsed = int.tryParse(ctrl.text.trim());
              if (parsed == null) return;
              Navigator.pop(ctx, parsed.clamp(5, 100));
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose);
    if (v != null) _finishToolOpacityAdjustment(v / 100.0);
  }

  Future<void> _promptTextFillTransparencyPercentNumeric(
    BuildContext panelContext,
  ) async {
    final ts = _settingsFor(_ToolType.text);
    final tgt = _primaryTextToolbarTarget();
    final alpha =
        (_colorPanelFillAlpha ??
                ((tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor).a /
                    255.0))
            .clamp(0.0, 1.0);
    final transparencyPct = ((1.0 - alpha) * 100).round().clamp(0, 100);
    final ctrl = TextEditingController(text: '$transparencyPct');
    final v = await showDialog<int>(
      context: panelContext,
      builder: (ctx) => AlertDialog(
        title: const Text('채움 투명도'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '0 ~ 100 (높을수록 더 투명)',
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
              final parsed = int.tryParse(ctrl.text.trim());
              if (parsed == null) return;
              Navigator.pop(ctx, parsed.clamp(0, 100));
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose),
    );
    if (v == null) return;
    _onTextColorPanelFillAlphaDragStart();
    _onTextColorPanelFillAlphaChanged(1.0 - v / 100.0);
  }

  void _cycleMemoCanvasRotation() {
    final page = _activeMemoPage;
    if (page == null) return;
    setState(() {
      page.canvasRotationQuarterTurns =
          (page.canvasRotationQuarterTurns + 1) % 4;
    });
    _markDirty();
  }

  void _setEraserMode(_EraserMode mode) {
    if (_eraserMode != mode && _tool == _ToolType.eraser) {
      _abortCanvasListenerPointerGesture(
        commitStrokeEraserIfChanged: _eraserMode == _EraserMode.stroke,
      );
    }
    setState(() {
      _eraserMode = mode;
      if (_tool == _ToolType.eraser &&
          _eraserMode == _EraserMode.stroke &&
          _dockTool == _ToolType.eraser &&
          _dockPanelKind == _ToolDockPanelKind.width) {
        _dockPanelKind = null;
      }
    });
    _markDirty();
  }

  /// [InteractiveViewer] already applies pinch zoom to [_transformController].
  /// Do not multiply the matrix again in interaction callbacks (that caused
  /// runaway tiny scales). Only repair obviously broken transforms.
  void _onMemoViewerInteractionEnd(ScaleEndDetails details) {
    _repairTransformIfCorrupt();
  }

  void _repairTransformIfCorrupt() {
    final s = _transformController.value.getMaxScaleOnAxis();
    if (!s.isFinite || s < 0.35 || s > 12) {
      _transformController.value = Matrix4.identity();
    }
  }

  void _resetMemoCanvasView() {
    _transformController.value = Matrix4.identity();
    _repairTransformIfCorrupt();
    setState(() {});
  }

  Offset _touchCenter() {
    final points = _touchPoints.values.toList(growable: false);
    final dx = points.fold<double>(0, (sum, point) => sum + point.dx);
    final dy = points.fold<double>(0, (sum, point) => sum + point.dy);
    return Offset(dx / points.length, dy / points.length);
  }

  /// Apply manual pinch + 2-finger pan from the active touch state.
  ///
  /// We deliberately do not use [InteractiveViewer]'s built-in scale recognizer
  /// because it claims pointers in the gesture arena. When an edit pointer is
  /// already active (pencil drawing, lasso drag, etc.), a second touch could
  /// otherwise hijack the gesture before [State.setState] gets a chance to
  /// flip `scaleEnabled`. Doing it manually keeps the lock check synchronous.
  void _applyTwoFingerCanvasPanIfNeeded() {
    if (!_isPageSwipeActive || _touchPoints.length < 2) return;
    if (_isCanvasEditGestureLocked()) return;
    final pts = _touchPoints.values.toList(growable: false);
    if (pts.length < 2) return;

    final startDist = _pageSwipeStartFingerDist;
    final startCenter = _twoFingerStartCenter;
    final startMatrix = _twoFingerStartMatrix;
    if (startDist == null ||
        startDist < 8 ||
        startCenter == null ||
        startMatrix == null) {
      return;
    }

    final dist = (pts[0] - pts[1]).distance;
    final center = (pts[0] + pts[1]) * 0.5;
    final rawScale = (dist / startDist).clamp(0.05, 20.0);

    // Clamp the resulting absolute scale to the same envelope the previous
    // InteractiveViewer setup used so pinch cannot overshoot.
    const minScale = 0.88;
    const maxScale = 5.0;
    final startScale = startMatrix.getMaxScaleOnAxis();
    final targetScale = (rawScale * startScale).clamp(minScale, maxScale);
    final effectiveScale = startScale == 0 ? 1.0 : targetScale / startScale;

    // newMatrix = T(center) · S(effectiveScale) · T(-startCenter) · startMatrix
    final delta = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(effectiveScale, effectiveScale, 1, 1)
      ..translateByDouble(-startCenter.dx, -startCenter.dy, 0, 1);
    _transformController.value = delta * startMatrix;
  }

  void _beginPageSwipe(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touchPoints[event.pointer] = event.localPosition;
    if (_touchPoints.length != 2) return;

    // Two-finger zoom/pan/swipe is allowed ONLY when no edit pointer is
    // currently active. The single-finger pencil/finger gesture that started
    // an edit (drawing, lasso, text drag, laser, …) must never be hijacked by
    // a stray secondary touch. The check is done synchronously here so we do
    // not rely on widget rebuilds for safety.
    if (_isCanvasEditGestureLocked()) {
      return;
    }

    final pts = _touchPoints.values.toList(growable: false);
    _pageSwipeStartFingerDist = (pts[0] - pts[1]).distance;
    _twoFingerStartCenter = (pts[0] + pts[1]) * 0.5;
    _twoFingerStartMatrix = _transformController.value.clone();

    _isPageSwipeActive = true;
    _pageSwipeStart = _touchCenter();
    _pageSwipeCurrent = _pageSwipeStart;
  }

  void _updatePageSwipe(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (!_touchPoints.containsKey(event.pointer)) return;
    _touchPoints[event.pointer] = event.localPosition;
    if (!_isPageSwipeActive || _touchPoints.length < 2) return;
    _pageSwipeCurrent = _touchCenter();
    _applyTwoFingerCanvasPanIfNeeded();
  }

  void _endPageSwipe(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (!_touchPoints.containsKey(event.pointer)) return;

    double? pinchSpreadRatio;
    if (_isPageSwipeActive && _touchPoints.length == 2) {
      final pts = _touchPoints.values.toList(growable: false);
      final d = (pts[0] - pts[1]).distance;
      final sd = _pageSwipeStartFingerDist;
      if (sd != null && sd > 8) {
        pinchSpreadRatio = d / sd;
      }
    }

    _touchPoints[event.pointer] = event.localPosition;
    if (_isPageSwipeActive && _touchPoints.length >= 2) {
      _pageSwipeCurrent = _touchCenter();
    }

    _touchPoints.remove(event.pointer);

    if (_isPageSwipeActive && _touchPoints.length < 2) {
      final start = _pageSwipeStart;
      final end = _pageSwipeCurrent;
      _isPageSwipeActive = false;
      _pageSwipeStart = null;
      _pageSwipeCurrent = null;
      _pageSwipeStartFingerDist = null;
      _twoFingerStartCenter = null;
      _twoFingerStartMatrix = null;
      // InteractiveViewer no longer drives pan/scale, so guard the matrix
      // ourselves at the end of every manual gesture.
      _repairTransformIfCorrupt();
      if (start == null || end == null) return;

      final pr = pinchSpreadRatio;
      if (pr != null && (pr - 1.0).abs() > 0.12) {
        return;
      }

      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      if (dx.abs() < 72) return;
      if (dx.abs() < dy.abs() * 1.2) return;
      _flipPageByHorizontalDelta(dx);
    }
  }

  void _handlePageScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (dx.abs() < 18) return;
    if (dx.abs() <= dy.abs()) return;
    _flipPageByHorizontalDelta(dx);
  }

  void _flipPageByHorizontalDelta(double dx) {
    final now = DateTime.now();
    final lastFlipAt = _lastPageFlipAt;
    if (lastFlipAt != null && now.difference(lastFlipAt).inMilliseconds < 220) {
      return;
    }

    final before = _safeActivePage;
    if (dx < 0) {
      _nextPage();
    } else {
      _prevPage();
    }
    if (_safeActivePage != before) {
      _lastPageFlipAt = now;
    }
  }

  void _cancelCanvasLongPressTimer() {
    _canvasLongPressTimer?.cancel();
    _canvasLongPressTimer = null;
    _longPressPointerId = null;
    _longPressOriginDoc = null;
    _longPressOriginGlobal = null;
  }

  void _scheduleCanvasLongPress(PointerDownEvent event, Size canvasSize) {
    final page = _activeMemoPage;
    if (page == null) return;

    if (_tool == _ToolType.lasso) {
      if (!_lassoFilterAllowsAny()) return;
      if (_hasLassoSelection) return;
      final doc = _documentPointFromPointer(event.localPosition, canvasSize);
      if (!_lassoLongPressPointIsClearOfObjects(doc, canvasSize, page)) {
        return;
      }
    } else if (_tool != _ToolType.text) {
      return;
    }

    _cancelCanvasLongPressTimer();
    _longPressPointerId = event.pointer;
    _longPressOriginDoc = _documentPointFromPointer(
      event.localPosition,
      canvasSize,
    );
    _longPressOriginGlobal = event.position;
    final delay = _tool == _ToolType.lasso
        ? const Duration(milliseconds: 1200)
        : const Duration(milliseconds: 1000);
    _canvasLongPressTimer = Timer(delay, () {
      if (!mounted) return;
      if (_tool != _ToolType.text && _tool != _ToolType.lasso) return;
      if (_longPressPointerId == null || _longPressOriginGlobal == null) {
        return;
      }
      if (_longPressOriginDoc == null) return;
      if (_tool == _ToolType.lasso) {
        if (_hasLassoSelection) return;
        if (!_lassoFilterAllowsAny()) return;
        final p = _activeMemoPage;
        final sz = _pointerCanvasSize;
        if (p == null || sz == null) return;
        if (!_lassoLongPressPointIsClearOfObjects(
          _longPressOriginDoc!,
          sz,
          p,
        )) {
          return;
        }
      }
      _showCanvasLongPressMenu(_longPressOriginGlobal!, _longPressOriginDoc!);
      _cancelCanvasLongPressTimer();
    });
  }

  void _maybeCancelLongPressFromMove(Offset local, Size canvasSize) {
    final origin = _longPressOriginDoc;
    if (origin == null) return;
    final p = _documentPointFromPointer(local, canvasSize);
    if ((p - origin).distance > 22) {
      _cancelCanvasLongPressTimer();
    }
  }

  void _showCanvasLongPressMenu(Offset global, Offset docAnchor) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    void dismiss() {
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (ctx) {
        final sz = MediaQuery.sizeOf(ctx);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => dismiss(),
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            Positioned(
              left: (global.dx - 70).clamp(6.0, sz.width - 146),
              top: (global.dy - 80).clamp(6.0, sz.height - 160),
              width: 140,
              child: Material(
                elevation: 10,
                borderRadius: BorderRadius.circular(10),
                color: AppColors.card,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_studioClipboard != null)
                      ListTile(
                        dense: true,
                        title: const Text('붙여넣기'),
                        onTap: () {
                          dismiss();
                          final c = _pointerCanvasSize;
                          if (c != null) {
                            unawaited(_pasteStudioClipboardAt(docAnchor, c));
                          }
                        },
                      ),
                    ListTile(
                      dense: true,
                      title: const Text('텍스트 상자'),
                      onTap: () {
                        dismiss();
                        final page = _activeMemoPage;
                        final c = _pointerCanvasSize;
                        if (page == null || c == null) return;
                        final clamped = _clampToCanvas(docAnchor, c);
                        final id = _addTextBoxAtCanvasPoint(clamped, c, page);
                        final box = _textBoxById(id);
                        if (box != null) {
                          _beginInlineTextEdit(box);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  void _cancelLaserTimers() {
    _laserClearTimer?.cancel();
    _laserClearTimer = null;
    _laserFadeTimer?.cancel();
    _laserFadeTimer = null;
    _laserDotHideTimer?.cancel();
    _laserDotHideTimer = null;
  }

  void _clearLaserOverlay() {
    _cancelLaserTimers();
    _laserTrail.clear();
    _laserDotDoc = null;
    _laserTrailOpacity = 1.0;
    _laserRepaint.value++;
    _syncInteractiveViewerGestureAvailability();
  }

  void _setLaserDismissMs(int ms) {
    final v = _normalizeLaserDismissMs(ms);
    setState(() {
      _settingsFor(_ToolType.laser).laserDismissMs = v;
    });
    _markDirty();
  }

  void _scheduleLaserDotHide() {
    _laserDotHideTimer?.cancel();
    _laserDotHideTimer = Timer(const Duration(milliseconds: 110), () {
      _laserDotHideTimer = null;
      if (!mounted) return;
      _laserDotDoc = null;
      _laserRepaint.value++;
      _syncInteractiveViewerGestureAvailability();
    });
  }

  /// Trail: hold then short fade-out (not persisted / not in undo).
  void _scheduleLaserTrailClear() {
    _cancelLaserTimers();
    final dismiss = _normalizeLaserDismissMs(
      _settingsFor(_ToolType.laser).laserDismissMs,
    );
    const fadeMs = 200;
    final holdMs = math.max(80, dismiss - fadeMs);
    _laserDiag('scheduleLaserTrailClear: hold=${holdMs}ms fade=${fadeMs}ms');
    _laserClearTimer = Timer(Duration(milliseconds: holdMs), () {
      _laserClearTimer = null;
      if (!mounted) return;
      _runLaserTrailFadeOut(fadeMs: fadeMs);
    });
  }

  void _runLaserTrailFadeOut({required int fadeMs}) {
    _laserFadeTimer?.cancel();
    final steps = (fadeMs / 28).ceil().clamp(4, 12);
    final stepMs = (fadeMs / steps).round().clamp(16, 55);
    var step = 0;
    _laserFadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) {
      if (!mounted) {
        t.cancel();
        _laserFadeTimer = null;
        return;
      }
      step++;
      _laserTrailOpacity = 1.0 - step / steps;
      if (_laserTrailOpacity < 0) _laserTrailOpacity = 0;
      _laserRepaint.value++;
      if (step >= steps) {
        t.cancel();
        _laserFadeTimer = null;
        _laserTrail.clear();
        _laserTrailOpacity = 1.0;
        _laserRepaint.value++;
        _laserDiag('laser trail fade done, cleared');
        _syncInteractiveViewerGestureAvailability();
      }
    });
  }

  void _startStroke(PointerDownEvent event, Size canvasSize) {
    _pointerCanvasSize = canvasSize;
    _beginPageSwipe(event);
    if (_tool == _ToolType.laser) {
      final drawingOk = _isDrawingEnabled(event);
      _laserDiag(
        'pointerDown -> _startStroke: tool=$_tool kind=${event.kind} '
        'drawingEnabled=$drawingOk stylusOnly=$_stylusOnly '
        'enforceStylusOnly=$_enforceStylusOnly pageSwipe=$_isPageSwipeActive '
        'activePointer=$_activePointer hasPage=${_activeMemoPage != null}',
      );
    }
    if (_isPageSwipeActive) {
      if (_tool == _ToolType.laser) {
        _laserDiag('pointerDown: BLOCKED (page swipe active)');
      }
      return;
    }
    if (_tool == _ToolType.lasso || _tool == _ToolType.text) {
      return;
    }
    if (!_isDrawingEnabled(event)) {
      if (_tool == _ToolType.laser) {
        _laserDiag('pointerDown: BLOCKED (_isDrawingEnabled false)');
      }
      return;
    }
    if (_activePointer != null) {
      if (_tool == _ToolType.laser) {
        _laserDiag(
          'pointerDown: BLOCKED (already activePointer=$_activePointer)',
        );
      }
      return;
    }
    if (_activeMemoPage == null) {
      if (_tool == _ToolType.laser) {
        _laserDiag('pointerDown: BLOCKED (no active memo page)');
      }
      return;
    }
    _activePointer = event.pointer;
    final clamped = _documentPointFromPointer(event.localPosition, canvasSize);
    if (_tool == _ToolType.laser) {
      _cancelLaserTimers();
      _laserTrail.clear();
      _laserDotDoc = null;
      _laserTrailOpacity = 1.0;
      final dotMode = _settingsFor(_ToolType.laser).laserModeIndex == 0;
      if (dotMode) {
        _laserDotDoc = clamped;
      } else {
        _laserTrail.add(clamped);
      }
      _recordDebugPointer(event.localPosition, canvasSize);
      _laserRepaint.value++;
      _laserDiag(
        'laser started: local=${event.localPosition} doc=$clamped '
        'dotMode=$dotMode trailLen=${_laserTrail.length} dot=${_laserDotDoc != null}',
      );
      _syncInteractiveViewerGestureAvailability();
      return;
    }
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      final page = _activeMemoPage;
      _pendingStrokeEraserUndo = page == null
          ? null
          : _StrokeListSnapshotUndo.fromStrokes(page.strokes);
    } else {
      _pendingStrokeEraserUndo = null;
    }
    _workingPoints = [clamped];
    _recordDebugPointer(event.localPosition, canvasSize);
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      _applyStrokeEraserAlongPath();
    }
    _notifyAnnotationLayer();
    _syncInteractiveViewerGestureAvailability();
  }

  void _appendStroke(PointerMoveEvent event, Size canvasSize) {
    _updatePageSwipe(event);
    if (_tool == _ToolType.lasso) {
      _lassoPointerMove(event, canvasSize);
      return;
    }
    if (_tool == _ToolType.text) {
      _textToolPointerMove(event, canvasSize);
      return;
    }
    if (_tool == _ToolType.laser) {
      if (_activePointer != event.pointer) {
        _laserDiag(
          'pointerMove laser: skip (pointer=${event.pointer} '
          'active=$_activePointer)',
        );
        return;
      }
      final clamped = _documentPointFromPointer(
        event.localPosition,
        canvasSize,
      );
      if (_settingsFor(_ToolType.laser).laserModeIndex == 0) {
        _laserDotDoc = clamped;
        _recordDebugPointer(event.localPosition, canvasSize);
        _laserRepaint.value++;
        return;
      }
      if (_laserTrail.isEmpty) {
        _laserDiag(
          'pointerMove laser: BLOCKED (_laserTrail empty — no matching down?)',
        );
        return;
      }
      _laserTrail.add(clamped);
      _recordDebugPointer(event.localPosition, canvasSize);
      _laserRepaint.value++;
      final n = _laserTrail.length;
      if (n == 2 || n % 25 == 0) {
        _laserDiag(
          'pointerMove laser: trailLen=$n lastDoc=$clamped _laserRepaint++',
        );
      }
      return;
    }
    if (_activePointer != event.pointer) return;
    if (_workingPoints == null) return;
    final clamped = _documentPointFromPointer(event.localPosition, canvasSize);
    _workingPoints!.add(clamped);
    _recordDebugPointer(event.localPosition, canvasSize);
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      _applyStrokeEraserAlongPath();
      _notifyStrokeEraserAnnotationIfDue();
    } else if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.pixel) {
      // Pixel eraser: collect path only; repainting every move freezes the UI.
    } else {
      _notifyAnnotationLayer();
    }
  }

  Offset _clampToCanvas(Offset point, Size size) {
    return Offset(
      point.dx.clamp(0, size.width),
      point.dy.clamp(0, size.height),
    );
  }

  /// Memo canvas / document coordinates used by every drawing tool.
  ///
  /// [InteractiveViewer] applies the inverse transform while hit testing, so
  /// [localInListener] from our [Listener] is already in the same plane as
  /// stored stroke points. Do **not** call [TransformationController.toScene]
  /// again (that double-transforms and misaligns ink under zoom/pan).
  Offset _documentPointFromPointer(Offset localInListener, Size canvasSize) {
    return _clampToCanvas(localInListener, canvasSize);
  }

  void _notifyStrokeEraserAnnotationIfDue() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastStrokeEraserAnnotMs >= 11) {
      _lastStrokeEraserAnnotMs = now;
      _annotationRepaint.value++;
    }
  }

  void _notifyAnnotationLayer() {
    _lastStrokeEraserAnnotMs = 0;
    _annotationRepaint.value++;
  }

  bool _strokeUndoSnapshotMatchesPage(
    _StrokeListSnapshotUndo snap,
    _CanvasPage page,
  ) {
    final cur = page.strokes;
    if (snap.strokesJson.length != cur.length) return false;
    for (var i = 0; i < cur.length; i++) {
      if (jsonEncode(snap.strokesJson[i]) != jsonEncode(cur[i].toJson())) {
        return false;
      }
    }
    return true;
  }

  void _recordDebugPointer(Offset localInListener, Size canvasSize) {
    if (!kDebugMode) return;
    _debugTouchDoc = localInListener;
    _debugAppliedDoc = _documentPointFromPointer(localInListener, canvasSize);
    _debugPointerRepaint.value++;
  }

  static const double _strokeEraseHitSlack = 6.0;

  double _strokeEraserHitRadius() =>
      _effectiveWidth * 0.7 + _strokeEraseHitSlack;

  void _applyStrokeEraserAlongPath() {
    final page = _activeMemoPage;
    final pts = _workingPoints;
    if (page == null || pts == null || pts.isEmpty) return;
    if (_tool != _ToolType.eraser || _eraserMode != _EraserMode.stroke) return;
    page.removeStrokesIntersectingDestructive(pts, _strokeEraserHitRadius());
  }

  _Stroke? _annotationWorkingPreview() {
    final pts = _workingPoints;
    if (_tool == _ToolType.laser) return null;
    if (pts == null || pts.length < 2) return null;
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.pixel) {
      return null;
    }
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      return null;
    }
    return _Stroke(
      id: '',
      points: pts,
      tool: _tool,
      color: _activeStrokeColor,
      width: _effectiveWidth,
    );
  }

  void _endStroke(PointerUpEvent event) {
    _cancelCanvasLongPressTimer();
    _endPageSwipe(event);
    if (_tool == _ToolType.lasso) {
      final sz = _pointerCanvasSize;
      if (sz != null) {
        _lassoPointerUp(event, sz);
      }
      return;
    }
    if (_tool == _ToolType.text) {
      final sz = _pointerCanvasSize;
      if (sz != null) {
        _textToolPointerUp(event, sz);
      }
      return;
    }
    if (_tool == _ToolType.laser) {
      if (_activePointer != event.pointer) {
        _laserDiag(
          'pointerUp laser: skip (pointer=${event.pointer} active=$_activePointer)',
        );
        return;
      }
      _activePointer = null;
      final dotMode = _settingsFor(_ToolType.laser).laserModeIndex == 0;
      if (dotMode) {
        _laserDiag('pointerUp laser: dot mode -> schedule hide');
        _scheduleLaserDotHide();
        _syncInteractiveViewerGestureAvailability();
        return;
      }
      if (_laserTrail.isEmpty) {
        _laserDiag('pointerUp laser: trail empty (cancel timers)');
        _cancelLaserTimers();
        _syncInteractiveViewerGestureAvailability();
        return;
      }
      _laserDiag(
        'pointerUp laser: trailLen=${_laserTrail.length} -> schedule fade',
      );
      _scheduleLaserTrailClear();
      _syncInteractiveViewerGestureAvailability();
      return;
    }
    if (_activePointer != event.pointer) return;
    final points = _workingPoints;
    _workingPoints = null;
    _activePointer = null;
    if (points == null || points.isEmpty) {
      setState(() {});
      _notifyAnnotationLayer();
      return;
    }

    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      _finalizeStrokeEraserUndoIfChanged();
      setState(() {});
      _notifyAnnotationLayer();
      return;
    }

    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.pixel) {
      final page = _activeMemoPage;
      if (page != null && points.isNotEmpty) {
        final pl = points.length >= 2
            ? points
            : <Offset>[points.first, points.first + const Offset(0.55, 0.55)];
        page.applyPixelEraserPolyline(pl, _effectiveWidth * 0.52 + 2.2, _uuid);
      }
      setState(() {});
      _notifyAnnotationLayer();
      _markDirty();
      return;
    }

    if (points.length < 2) {
      setState(() {});
      _notifyAnnotationLayer();
      return;
    }

    final stroke = _Stroke(
      id: _uuid.v4(),
      points: points,
      tool: _tool,
      color: _activeStrokeColor,
      width: _effectiveWidth,
    );
    _activeMemoPage?.addStroke(stroke);
    setState(() {});
    _notifyAnnotationLayer();
    _markDirty();
  }

  void _cancelStroke(PointerCancelEvent event) {
    _cancelCanvasLongPressTimer();
    _endPageSwipe(event);
    if (_tool == _ToolType.lasso) {
      _lassoPointerCancel(event);
      return;
    }
    if (_tool == _ToolType.text) {
      _textToolPointerCancel(event);
      return;
    }
    if (_tool == _ToolType.laser) {
      if (_activePointer != event.pointer) return;
      _activePointer = null;
      _laserDiag('pointerCancel laser: clearing transient overlay');
      _clearLaserOverlay();
      return;
    }
    if (_activePointer != event.pointer) return;
    if (_tool == _ToolType.eraser && _eraserMode == _EraserMode.stroke) {
      final page = _activeMemoPage;
      final pending = _pendingStrokeEraserUndo;
      _pendingStrokeEraserUndo = null;
      if (page != null && pending != null) {
        page.replaceStrokesFromUndoSnapshot(pending);
      }
    }
    _workingPoints = null;
    _activePointer = null;
    setState(() {});
    _notifyAnnotationLayer();
  }

  void _undo() {
    final page = _activeMemoPage;
    if (page == null || !page.canUndo) return;
    setState(() {
      page.undoLast();
      _pruneStaleSelections();
    });
    _notifyAnnotationLayer();
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _redo() {
    final page = _activeMemoPage;
    if (page == null || !page.canRedo) return;
    setState(() {
      page.redo();
      _pruneStaleSelections();
    });
    _notifyAnnotationLayer();
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _clear() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('현재 페이지 지우기'),
        content: const Text('이 페이지의 필기를 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _activeMemoPage?.clear());
              _markDirty();
            },
            child: const Text('지우기'),
          ),
        ],
      ),
    );
  }

  Future<void> _onDeleteCurrentPagePressed() async {
    final memo = _activeMemo;
    if (memo == null || !mounted) return;
    if (memo.pages.length <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마지막 페이지는 삭제할 수 없습니다.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('페이지 삭제'),
        content: const Text('현재 페이지를 삭제할까요? 이 작업은 되돌리기 어려울 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final memoNow = _activeMemo;
    if (memoNow == null) return;
    if (memoNow.pages.length <= 1) return;
    final idx = _safeActivePage;
    if (idx < 0 || idx >= memoNow.pages.length) return;
    final removed = memoNow.pages[idx];
    final imagePaths = removed.placedImages.map((e) => e.storagePath).toList();

    setState(() {
      memoNow.pages.removeAt(idx);
      _clearLaserOverlay();
      if (idx < memoNow.pages.length) {
        _activePage = idx;
      } else {
        _activePage = idx - 1;
      }
      _clearSelection();
      _clearLassoInteraction();
    });
    for (final p in imagePaths) {
      unawaited(_deleteFileQuietly(p));
    }
    _markDirty();
  }

  Widget _canvasMemoTextBox(_CanvasTextBox t, Size canvasSize) {
    final editing = _textEditingId == t.id;
    return ListenableBuilder(
      listenable: Listenable.merge([
        _textLayerRepaint,
        if (editing && _textEditController != null) _textEditController!,
      ]),
      builder: (context, _) {
        return _CanvasTextObjectView(
          box: t,
          canvasSize: canvasSize,
          textToolActive: _tool == _ToolType.text,
          selected: _selectedTextIds.contains(t.id),
          editing: editing,
          editController: _textEditController,
          editFocus: _textFieldFocus,
        );
      },
    );
  }

  // ── Session persistence ──────────────────────────────────────

  Future<void> _restoreSession() async {
    try {
      final raw = await _storage.readString(_sessionKey);
      if (raw == null || raw.trim().isEmpty) {
        _initDefaultSession();
        return;
      }
      final decodedRaw = jsonDecode(raw);
      if (decodedRaw is! Map) {
        _initDefaultSession();
        return;
      }
      final decoded = Map<String, dynamic>.from(decodedRaw);
      final version = _mpInt(decoded, 'version', 1);

      if (version < 2) {
        _migrateFromV1(decoded);
        return;
      }

      final foldersJson = decoded['folders'] as List<dynamic>? ?? const [];
      final memosJson = decoded['memos'] as List<dynamic>? ?? const [];
      final pdfsJson = decoded['pdfs'] as List<dynamic>? ?? const [];

      final folders = <_Folder>[];
      for (final item in foldersJson) {
        if (item is! Map) continue;
        try {
          final folder = _Folder.fromJson(Map<String, dynamic>.from(item));
          if (folder.id.isEmpty || folder.name.trim().isEmpty) continue;
          folders.add(folder);
        } catch (_) {}
      }
      final memos = <_Memo>[];
      for (final item in memosJson) {
        if (item is! Map) continue;
        try {
          final memo = _Memo.fromJson(Map<String, dynamic>.from(item));
          if (memo.id.isEmpty || memo.folderId.isEmpty) continue;
          memos.add(memo);
        } catch (_) {}
      }
      final pdfs = <_PdfAsset>[];
      for (final item in pdfsJson.whereType<Map>()) {
        try {
          final model = _PdfAsset.fromJson(Map<String, dynamic>.from(item));
          if (model.id.isEmpty || model.path.isEmpty) continue;
          if (await File(model.path).exists()) pdfs.add(model);
        } catch (_) {}
      }

      if (!mounted) return;
      if (folders.isEmpty) {
        _initDefaultSession();
        return;
      }

      final savedFolderId = decoded['activeFolderId']?.toString();
      final savedMemoId = decoded['activeMemoId']?.toString();
      final savedPage = _mpInt(decoded, 'activePage', 0);

      final activeFolderId = folders.any((f) => f.id == savedFolderId)
          ? savedFolderId
          : folders.first.id;
      final activeMemoId = memos.any((m) => m.id == savedMemoId)
          ? savedMemoId
          : (memos.isNotEmpty ? memos.first.id : null);

      final activeMemo = memos.where((m) => m.id == activeMemoId).firstOrNull;
      final clampedPage = activeMemo == null || activeMemo.pages.isEmpty
          ? 0
          : savedPage.clamp(0, activeMemo.pages.length - 1);

      setState(() {
        _folders = folders;
        _memos = memos;
        _uploadedPdfs = pdfs;
        _activeFolderId = activeFolderId;
        _activeMemoId = activeMemoId;
        _activePage = clampedPage;
        var restoredTool =
            _ToolType.values[_mpInt(
              decoded,
              'tool',
              _ToolType.pen.index,
            ).clamp(0, _ToolType.values.length - 1)];
        if (restoredTool == _ToolType.hand) {
          restoredTool = _ToolType.pen;
        }
        _tool = restoredTool;
        _eraserMode =
            _EraserMode.values[_mpInt(
              decoded,
              'eraserMode',
              _EraserMode.pixel.index,
            ).clamp(0, _EraserMode.values.length - 1)];
        _paperStyle =
            _PaperStyle.values[_mpInt(
              decoded,
              'paperStyle',
              _PaperStyle.ruled.index,
            ).clamp(0, _PaperStyle.values.length - 1)];
        final savedToolSettings = decoded['toolSettings'] is Map
            ? Map<String, dynamic>.from(decoded['toolSettings'] as Map)
            : null;
        for (final tool in _ToolType.values) {
          if (tool == _ToolType.hand || tool == _ToolType.lasso) continue;
          final fallback = _defaultToolSettings(tool);
          final saved = savedToolSettings?[tool.name];
          _toolSettings[tool] = saved is Map
              ? _ToolSettings.fromJson(
                  Map<String, dynamic>.from(saved),
                  fallback: fallback,
                )
              : fallback;
        }
        final recentColorsJson = decoded['recentColors'];
        if (recentColorsJson != null && recentColorsJson.isNotEmpty) {
          _recentColors = recentColorsJson
              .whereType<Object>()
              .map((value) => _mpColor(value, _memoDefaultInkColor))
              .toList()
              .take(6)
              .toList();
        }
        final legacyColorRaw = decoded['color'];
        final legacyColor = legacyColorRaw == null
            ? null
            : _mpColor(legacyColorRaw, _memoDefaultInkColor);
        final activeSettings = _settingsFor(_tool);
        final legacyWidth = decoded['width'] == null
            ? null
            : _mpDouble(decoded, 'width', activeSettings.width);
        if (legacyColor != null || legacyWidth != null) {
          if (legacyColor != null) {
            activeSettings.color = legacyColor;
          }
          if (legacyWidth != null) {
            activeSettings.width = legacyWidth;
          }
        }
        _stylusOnly = decoded['stylusOnly'] as bool? ?? true;
        _lassoFilterText = decoded['lassoFilterText'] as bool? ?? true;
        _lassoFilterDrawing = decoded['lassoFilterDrawing'] as bool? ?? true;
        _lassoFilterImage = decoded['lassoFilterImage'] as bool? ?? true;
        _isRestoring = false;
      });
    } catch (_) {
      if (!mounted) return;
      _initDefaultSession();
    } finally {
      if (mounted && _isRestoring) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  void _initDefaultSession() {
    final folder = _Folder(
      id: _uuid.v4(),
      name: '기본 폴더',
      color: const Color(0xFF4DA3FF),
    );
    final memo = _Memo(id: _uuid.v4(), name: '메모 1', folderId: folder.id);
    setState(() {
      _folders = [folder];
      _memos = [memo];
      _activeFolderId = folder.id;
      _activeMemoId = memo.id;
      _activePage = 0;
      _isRestoring = false;
    });
  }

  void _migrateFromV1(Map<String, dynamic> decoded) {
    final folder = _Folder(
      id: _uuid.v4(),
      name: '기본 폴더',
      color: const Color(0xFF4DA3FF),
    );
    final pagesJson = decoded['pages'] as List<dynamic>? ?? const [];
    final pages = pagesJson
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => _CanvasPage.fromJson(
            m,
            legacyMemoPdfId: decoded['activePdfId'] as String?,
            memoLegacyCanvasRotation: 0,
          ),
        )
        .toList();
    final memo = _Memo(
      id: _uuid.v4(),
      name: '메모 1',
      folderId: folder.id,
      pages: pages.isEmpty ? [_CanvasPage.createDefaultMemoPage()] : pages,
      pdfId: decoded['activePdfId'] as String?,
    );
    if (!mounted) return;
    setState(() {
      _folders = [folder];
      _memos = [memo];
      _activeFolderId = folder.id;
      _activeMemoId = memo.id;
      _activePage = 0;
      _isRestoring = false;
    });
    _markDirty();
  }

  Future<void> _persistSession() async {
    if (!mounted) return;
    try {
      final payload = {
        'version': 4,
        'activeFolderId': _activeFolderId,
        'activeMemoId': _activeMemoId,
        'activePage': _activePage,
        'tool': _tool.index,
        'eraserMode': _eraserMode.index,
        'paperStyle': _paperStyle.index,
        'toolSettings': {
          for (final entry in _toolSettings.entries)
            if (entry.key != _ToolType.hand && entry.key != _ToolType.lasso)
              entry.key.name: entry.value.toJson(),
        },
        'lassoFilterText': _lassoFilterText,
        'lassoFilterDrawing': _lassoFilterDrawing,
        'lassoFilterImage': _lassoFilterImage,
        'recentColors': _recentColors.map((color) => color.toARGB32()).toList(),
        'stylusOnly': _stylusOnly,
        'folders': _folders.map((f) => f.toJson()).toList(),
        'memos': _memos.map((m) => m.toJson()).toList(),
        'pdfs': _uploadedPdfs.map((p) => p.toJson()).toList(),
      };
      await _storage.writeString(_sessionKey, jsonEncode(payload));
    } catch (_) {
      // Avoid surfacing storage/json failures as crashes; user keeps working.
    }
  }

  _CanvasTextBox? _primaryTextToolbarTarget() {
    if (_textEditingId != null) return _textBoxById(_textEditingId!);
    if (_selectedTextIds.length == 1) {
      return _textBoxById(_selectedTextIds.first);
    }
    return null;
  }

  Future<void> _openTextFontPicker(BuildContext context) async {
    final ts = _settingsFor(_ToolType.text);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('글꼴'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Pretendard'),
            child: const Text('Pretendard'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('시스템 기본'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          t.fontFamily = choice;
          t.markUpdated();
        });
      } else {
        ts.textFontFamily = choice;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  /// v1: typography toggles always apply to the full [_CanvasTextBox], not a selection range.
  void _toggleTextToolbarBold() {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          t.bold = !t.bold;
          t.markUpdated();
        });
      } else {
        ts.bold = !ts.bold;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _toggleTextToolbarItalic() {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          t.italic = !t.italic;
          t.markUpdated();
        });
      } else {
        ts.italic = !ts.italic;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _toggleTextToolbarUnderline() {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          t.underline = !t.underline;
          t.markUpdated();
        });
      } else {
        ts.textUnderline = !ts.textUnderline;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _setTextToolbarAlign(int index) {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          t.textAlignIndex = index;
          t.markUpdated();
        });
      } else {
        ts.textAlignIndex = index;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _toggleTextToolbarBackground() {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        var anyOn = false;
        _forEachToolbarTextBox((t) {
          if (t.hasBackground) {
            t.hasBackground = false;
          } else {
            t.hasBackground = true;
            t.backgroundColor = const Color(0x66FACC15);
          }
          t.markUpdated();
          if (t.hasBackground) anyOn = true;
        });
        if (anyOn) {
          _textStyleColorTarget = _TextStyleColorTarget.fill;
        }
      } else {
        if (ts.textBoxNextHasBackground) {
          ts.textBoxNextHasBackground = false;
        } else {
          ts.textBoxNextHasBackground = true;
          if (ts.textBoxNextBackgroundColor.a < 0.1) {
            ts.textBoxNextBackgroundColor = const Color(0x66FACC15);
          }
        }
        if (ts.textBoxNextHasBackground) {
          _textStyleColorTarget = _TextStyleColorTarget.fill;
        }
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _toggleTextToolbarBorder() {
    final ts = _settingsFor(_ToolType.text);
    _pushFullTextLayoutUndo();
    setState(() {
      if (_textToolbarAffectsPlacedTextBoxes()) {
        var anyOn = false;
        _forEachToolbarTextBox((t) {
          t.hasBorder = !t.hasBorder;
          if (t.hasBorder && t.borderColor.a < 0.1) {
            t.borderColor = const Color(0xFF6B7280);
          }
          t.markUpdated();
          if (t.hasBorder) anyOn = true;
        });
        if (anyOn) {
          _textStyleColorTarget = _TextStyleColorTarget.border;
        }
      } else {
        ts.textBoxNextHasBorder = !ts.textBoxNextHasBorder;
        if (ts.textBoxNextHasBorder && ts.textBoxNextBorderColor.a < 0.1) {
          ts.textBoxNextBorderColor = const Color(0xFF6B7280);
        }
        if (ts.textBoxNextHasBorder) {
          _textStyleColorTarget = _TextStyleColorTarget.border;
        }
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _setTextStyleColorTarget(_TextStyleColorTarget t) {
    if (_textStyleColorTarget == t) return;
    setState(() {
      _textStyleColorTarget = t;
      if (_tool == _ToolType.text &&
          _dockPanelKind == _ToolDockPanelKind.color &&
          t == _TextStyleColorTarget.fill) {
        final ts = _settingsFor(_ToolType.text);
        final tgt = _primaryTextToolbarTarget();
        final c = tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor;
        _colorPanelFillAlpha = c.a / 255.0;
      } else if (t != _TextStyleColorTarget.fill) {
        _colorPanelFillAlpha = null;
      }
    });
  }

  void _stepTextFontSize(int delta) {
    final cur = _activeWidth;
    final next = (cur + delta).clamp(8.0, 72.0);
    if (next == cur) return;
    _finishToolWidthAdjustment(next);
  }

  void _onTextColorPanelFillAlphaChanged(double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    setState(() {
      _colorPanelFillAlpha = a;
      final ts = _settingsFor(_ToolType.text);
      final tgt = _primaryTextToolbarTarget();
      final base = tgt?.backgroundColor ?? ts.textBoxNextBackgroundColor;
      final merged = base.withValues(alpha: a);
      if (_textToolbarAffectsPlacedTextBoxes()) {
        _forEachToolbarTextBox((t) {
          final b = t.backgroundColor;
          t.backgroundColor = b.withValues(alpha: a);
          t.hasBackground = true;
          t.markUpdated();
        });
      } else if (tgt != null) {
        tgt.backgroundColor = merged;
        tgt.hasBackground = true;
      } else {
        ts.textBoxNextBackgroundColor = merged;
        ts.textBoxNextHasBackground = true;
      }
    });
    _textLayerRepaint.value++;
    _markDirty();
  }

  void _onTextColorPanelFillAlphaDragStart() {
    _pushFullTextLayoutUndo();
  }

  Future<void> _openTextFontSizePopover(BuildContext anchorContext) async {
    const presets = <int>[
      8,
      10,
      12,
      14,
      16,
      18,
      20,
      24,
      28,
      32,
      36,
      48,
      64,
      72,
    ];
    final ctrl = TextEditingController(text: _activeWidth.round().toString());
    double? picked;
    try {
      picked = await showDialog<double>(
        context: anchorContext,
        builder: (ctx) => AlertDialog(
          title: const Text('글자 크기'),
          content: SizedBox(
            width: 280,
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '대표 크기',
                  style: TextStyle(
                    color: AppColors.subText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    children: [
                      for (final s in presets)
                        ListTile(
                          dense: true,
                          title: Text('$s'),
                          onTap: () => Navigator.pop(ctx, s.toDouble()),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '직접 입력 (8–72)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim(),
                );
                if (v == null) return;
                Navigator.pop(ctx, v.clamp(8.0, 72.0));
              },
              child: const Text('적용'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (picked != null && mounted) {
      _finishToolWidthAdjustment(picked);
    }
  }

  _TextDockBindings _buildTextDockBindings(BuildContext context) {
    final ts = _settingsFor(_ToolType.text);
    final t = _primaryTextToolbarTarget();
    String fontLabel() {
      final fam = (t?.fontFamily ?? ts.textFontFamily).trim();
      if (fam.isEmpty) return '시스템';
      if (fam == 'Pretendard') return 'Pretendard';
      return fam.length > 8 ? '${fam.substring(0, 8)}…' : fam;
    }

    return _TextDockBindings(
      fontShortLabel: fontLabel(),
      fontSizeRound: _activeWidth.round(),
      bold: t?.bold ?? ts.bold,
      italic: t?.italic ?? ts.italic,
      underline: t?.underline ?? ts.textUnderline,
      alignIndex: t?.textAlignIndex ?? ts.textAlignIndex,
      hasBackground: t?.hasBackground ?? ts.textBoxNextHasBackground,
      hasBorder: t?.hasBorder ?? ts.textBoxNextHasBorder,
      colorTarget: _textStyleColorTarget,
      onFontMenu: () => unawaited(_openTextFontPicker(context)),
      onDecFontSize: () => _stepTextFontSize(-1),
      onIncFontSize: () => _stepTextFontSize(1),
      onFontSizeNumberTap: (c) => unawaited(_openTextFontSizePopover(c)),
      onPickColor: _openToolColorPanel,
      onColorTarget: _setTextStyleColorTarget,
      onBold: _toggleTextToolbarBold,
      onItalic: _toggleTextToolbarItalic,
      onUnderline: _toggleTextToolbarUnderline,
      onAlignLeft: () => _setTextToolbarAlign(0),
      onAlignCenter: () => _setTextToolbarAlign(1),
      onAlignRight: () => _setTextToolbarAlign(2),
      onToggleBg: _toggleTextToolbarBackground,
      onToggleBorder: _toggleTextToolbarBorder,
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isIPadLike =
        Theme.of(context).platform == TargetPlatform.iOS &&
        Responsive.isTabletOrLarger(context);
    _enforceStylusOnly = isIPadLike;

    if (_isRestoring) {
      return AdaptiveScaffold(
        currentIndex: 3,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '자료를 불러오는 중…',
                style: TextStyle(
                  color: AppColors.subText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final memo = _activeMemo;
    final pageCount = memo?.pages.length ?? 0;
    final activePage = pageCount == 0 ? 0 : _safeActivePage;
    final memoPdfStrip = memo == null
        ? const <_PdfAsset>[]
        : _uploadedPdfs
              .where((p) => _memoReferencesPdfAsset(memo, p.id))
              .toList();

    return AdaptiveScaffold(
      currentIndex: 3,
      body: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Container(
          color: AppColors.background,
          child: SafeArea(
            child: Row(
              children: [
                // ── Left sidebar ──────────────────────────────────
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: _isStudioPanelCollapsed
                      ? _studioPanelCollapsedWidth
                      : _studioPanelExpandedWidth,
                  child: _isStudioPanelCollapsed
                      ? _CollapsedStudioPanelTab(
                          onExpand: () =>
                              setState(() => _isStudioPanelCollapsed = false),
                        )
                      : _SidePanel(
                          folders: _folders,
                          memos: _memos,
                          activeMemoId: _activeMemoId,
                          onAddFolder: _addFolder,
                          onDeleteFolder: _deleteFolder,
                          onRenameFolder: _renameFolder,
                          onAddMemo: _addMemo,
                          onDeleteMemo: _deleteMemo,
                          onRenameMemo: _renameMemo,
                          onSelectMemo: _selectMemo,
                          onCollapse: () =>
                              setState(() => _isStudioPanelCollapsed = true),
                          onToggleFolder: (folderId) {
                            setState(() {
                              final idx = _folders.indexWhere(
                                (f) => f.id == folderId,
                              );
                              if (idx >= 0) {
                                _folders[idx].isExpanded =
                                    !_folders[idx].isExpanded;
                              }
                            });
                          },
                        ),
                ),
                // ── Canvas area ───────────────────────────────────
                Expanded(
                  child: Column(
                    children: [
                      _TopStudioBar(
                        activeMemoName: memo?.name ?? '메모 없음',
                        activePage: activePage,
                        pageCount: pageCount,
                        paperStyle: _paperStyle,
                        stylusOnly: _enforceStylusOnly ? _stylusOnly : false,
                        showStylusToggle: _enforceStylusOnly,
                        onUploadPdf: _uploadPdf,
                        onPrevPage: _prevPage,
                        onNextPage: _nextPage,
                        onAddPage: _addPage,
                        onRotateCanvas: _cycleMemoCanvasRotation,
                        onAddImage: _addImageToCanvas,
                        onOpenPageNavigator: _openMemoPageNavigator,
                        onResetCanvasView: _resetMemoCanvasView,
                        onPaperStyleChange: (style) {
                          setState(() => _paperStyle = style);
                          _markDirty();
                        },
                        onToggleStylusOnly: () {
                          if (!_enforceStylusOnly) return;
                          setState(() => _stylusOnly = !_stylusOnly);
                          _markDirty();
                        },
                      ),
                      if (memoPdfStrip.isNotEmpty)
                        _PdfStrip(
                          pdfs: memoPdfStrip,
                          activePdfId: memo?.pdfId,
                          expanded: _pdfStripExpanded,
                          onToggleExpand: () => setState(
                            () => _pdfStripExpanded = !_pdfStripExpanded,
                          ),
                          onSelect: (pdfId) {
                            setState(() {
                              memo?.pdfId = pdfId;
                              _pdfStripExpanded = false;
                            });
                            _markDirty();
                          },
                          onRemove: _removePdf,
                        ),
                      LayoutBuilder(
                        builder: (context, dockConstraints) {
                          final dockW = math
                              .min(dockConstraints.maxWidth - 20, 980.0)
                              .clamp(120.0, 980.0);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: SizedBox(
                                    width: dockW,
                                    child: _ToolDock(
                                      tool: _tool,
                                      dockPanel: _isDockOpen
                                          ? _dockPanelKind
                                          : null,
                                      lassoTextSelectionCount:
                                          _tool == _ToolType.lasso
                                          ? _selectedTextIds.length
                                          : 0,
                                      recentColors: _recentColors,
                                      width: _activeWidth,
                                      color: _toolbarColorPreview,
                                      opacity: _activeOpacity,
                                      eraserMode: _eraserMode,
                                      laserModeIndex: _settingsFor(
                                        _ToolType.laser,
                                      ).laserModeIndex,
                                      laserDismissMs: _settingsFor(
                                        _ToolType.laser,
                                      ).laserDismissMs,
                                      onLaserDismissMsChanged:
                                          _setLaserDismissMs,
                                      textColorTargetLabel:
                                          _tool == _ToolType.text
                                          ? switch (_textStyleColorTarget) {
                                              _TextStyleColorTarget.text =>
                                                '텍스트',
                                              _TextStyleColorTarget.fill =>
                                                '채움',
                                              _TextStyleColorTarget.border =>
                                                '테두리',
                                            }
                                          : null,
                                      attachTextFormatRowBelow:
                                          _showTextAuxiliaryBar,
                                      onToolChange: _setTool,
                                      onToggleEraserMode: () {
                                        _setEraserMode(
                                          _eraserMode == _EraserMode.pixel
                                              ? _EraserMode.stroke
                                              : _EraserMode.pixel,
                                        );
                                      },
                                      onWidthChange: _updateActiveToolWidth,
                                      onWidthChangeEnd:
                                          _finishToolWidthAdjustment,
                                      onOpacityChange: _updateActiveToolOpacity,
                                      onOpacityChangeEnd:
                                          _finishToolOpacityAdjustment,
                                      onColorChange: _updateActiveToolColor,
                                      onColorCircleTap: _openToolColorPanel,
                                      onAdvancedColorFromPanel: () =>
                                          _openAdvancedColorPicker(
                                            editOpacity:
                                                _tool !=
                                                    _ToolType.highlighter &&
                                                _tool != _ToolType.lasso &&
                                                (_tool != _ToolType.text ||
                                                    _textStyleColorTarget ==
                                                        _TextStyleColorTarget
                                                            .fill),
                                          ),
                                      textFillAlphaForPanel:
                                          _tool == _ToolType.text &&
                                              _isDockOpen &&
                                              _dockPanelKind ==
                                                  _ToolDockPanelKind.color &&
                                              _textStyleColorTarget ==
                                                  _TextStyleColorTarget.fill
                                          ? (_colorPanelFillAlpha ??
                                                (() {
                                                  final ts = _settingsFor(
                                                    _ToolType.text,
                                                  );
                                                  final tgt =
                                                      _primaryTextToolbarTarget();
                                                  final c =
                                                      tgt?.backgroundColor ??
                                                      ts.textBoxNextBackgroundColor;
                                                  return c.a / 255.0;
                                                })())
                                          : null,
                                      onTextFillAlphaChanged:
                                          _tool == _ToolType.text &&
                                              _isDockOpen &&
                                              _dockPanelKind ==
                                                  _ToolDockPanelKind.color &&
                                              _textStyleColorTarget ==
                                                  _TextStyleColorTarget.fill
                                          ? _onTextColorPanelFillAlphaChanged
                                          : null,
                                      onTextFillAlphaDragStart:
                                          _tool == _ToolType.text &&
                                              _isDockOpen &&
                                              _dockPanelKind ==
                                                  _ToolDockPanelKind.color &&
                                              _textStyleColorTarget ==
                                                  _TextStyleColorTarget.fill
                                          ? _onTextColorPanelFillAlphaDragStart
                                          : null,
                                      onTextFillAlphaChangeEnd: null,
                                      onTextFillAlphaValueTap:
                                          _tool == _ToolType.text &&
                                              _isDockOpen &&
                                              _dockPanelKind ==
                                                  _ToolDockPanelKind.color &&
                                              _textStyleColorTarget ==
                                                  _TextStyleColorTarget.fill
                                          ? _promptTextFillTransparencyPercentNumeric
                                          : null,
                                      onWidthChipTap: _openToolWidthPanel,
                                      onWidthValueTap: _promptWidthNumeric,
                                      onOpacityValueTap:
                                          _promptOpacityPercentNumeric,
                                      undoEnabled:
                                          _activeMemoPage?.canUndo ?? false,
                                      redoEnabled:
                                          _activeMemoPage?.canRedo ?? false,
                                      onUndo: _undo,
                                      onRedo: _redo,
                                      onClear: _clear,
                                      onDeleteCurrentPage:
                                          _onDeleteCurrentPagePressed,
                                      onCloseDockPanel: () {
                                        setState(() {
                                          _dockPanelKind = null;
                                          _colorPanelFillAlpha = null;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                if (_showTextAuxiliaryBar) ...[
                                  const SizedBox(height: 2),
                                  Center(
                                    child: SizedBox(
                                      width: dockW,
                                      child: _TextAuxiliarySettingsBar(
                                        width: dockW,
                                        attachedBelowMainDock: true,
                                        bindings: _buildTextDockBindings(
                                          context,
                                        ),
                                        onClose: () => setState(
                                          () => _textAuxiliaryBarHidden = true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final canvasPage = _activeMemoPage;
                            final pdfAsset = canvasPage == null
                                ? null
                                : _pdfAssetForCanvasPage(canvasPage);
                            final pdfPageIdx =
                                pdfAsset == null || canvasPage == null
                                ? 0
                                : _pdfRenderPageIndexFor(pdfAsset, canvasPage);
                            String? importBgPath;
                            if (canvasPage != null &&
                                canvasPage.kind ==
                                    _CanvasPageKind.importedImage) {
                              importBgPath = canvasPage.sourceImagePath;
                            }
                            final hasRasterBackground =
                                pdfAsset != null ||
                                (importBgPath != null &&
                                    importBgPath.isNotEmpty);
                            final canvasTurns =
                                canvasPage?.canvasRotationQuarterTurns ?? 0;
                            final pdfBoxFit =
                                memo?.pdfDisplayMode ==
                                    _PdfDisplayMode.stretchToMemo
                                ? BoxFit.fill
                                : BoxFit.contain;
                            final dpr = MediaQuery.devicePixelRatioOf(context);
                            final memoPaperW = math.min(
                              constraints.maxWidth * 0.96,
                              constraints.maxHeight * 0.98 / 1.414,
                            );
                            final pdfRenderWidth = (memoPaperW * dpr * 2.2)
                                .round()
                                .clamp(480, 1400);
                            return Center(
                              child: KeyedSubtree(
                                key: _memoEditViewportKey,
                                child: Container(
                                  width: constraints.maxWidth * 0.96,
                                  height: constraints.maxHeight * 0.98,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardAlt,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: AppColors.line),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: RotatedBox(
                                      quarterTurns: canvasTurns % 4,
                                      child: InteractiveViewer(
                                        transformationController:
                                            _transformController,
                                        minScale: 0.88,
                                        maxScale: 5.0,
                                        panEnabled: false,
                                        scaleEnabled:
                                            !_isCanvasEditGestureLocked(),
                                        onInteractionEnd:
                                            _onMemoViewerInteractionEnd,
                                        boundaryMargin: const EdgeInsets.all(
                                          120,
                                        ),
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: 1 / 1.414,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (pdfAsset != null)
                                                  RepaintBoundary(
                                                    child: _PdfCanvasBackground(
                                                      pdfPath: pdfAsset.path,
                                                      pageIndex: pdfPageIdx,
                                                      boxFit: pdfBoxFit,
                                                      maxRenderWidth:
                                                          pdfRenderWidth,
                                                    ),
                                                  ),
                                                if (importBgPath != null &&
                                                    importBgPath.isNotEmpty)
                                                  RepaintBoundary(
                                                    child: ColoredBox(
                                                      color: Colors.white,
                                                      child: Image.file(
                                                        File(importBgPath),
                                                        fit: pdfBoxFit,
                                                        filterQuality:
                                                            FilterQuality
                                                                .medium,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) => const Center(
                                                              child: Icon(
                                                                Icons
                                                                    .broken_image_outlined,
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                LayoutBuilder(
                                                  builder: (ctx, c) {
                                                    final canvasSize = Size(
                                                      c.maxWidth,
                                                      c.maxHeight,
                                                    );
                                                    if (_liveCanvasSize !=
                                                        canvasSize) {
                                                      _liveCanvasSize =
                                                          canvasSize;
                                                    }
                                                    final page =
                                                        _activeMemoPage;
                                                    final sortedImages =
                                                        page == null
                                                        ? const <_PlacedImage>[]
                                                        : (page.placedImages
                                                              .toList()
                                                            ..sort(
                                                              (a, b) => a.zIndex
                                                                  .compareTo(
                                                                    b.zIndex,
                                                                  ),
                                                            ));
                                                    final imageDpr =
                                                        MediaQuery.devicePixelRatioOf(
                                                          ctx,
                                                        );
                                                    return RepaintBoundary(
                                                      child: Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          Listener(
                                                            behavior:
                                                                HitTestBehavior
                                                                    .opaque,
                                                            onPointerSignal:
                                                                _handlePageScroll,
                                                            onPointerDown: (e) {
                                                              _scheduleCanvasLongPress(
                                                                e,
                                                                canvasSize,
                                                              );
                                                              if (_tool ==
                                                                  _ToolType
                                                                      .laser) {
                                                                _laserDiag(
                                                                  'canvas Listener '
                                                                  'onPointerDown: '
                                                                  'textLayerAbsorbsPointers='
                                                                  '$_textCanvasLayerAbsorbsPointers '
                                                                  '(false=laser reaches Listener) '
                                                                  'kind=${e.kind}',
                                                                );
                                                              }
                                                              if (_tool ==
                                                                  _ToolType
                                                                      .lasso) {
                                                                _lassoPointerDown(
                                                                  e,
                                                                  canvasSize,
                                                                );
                                                              } else if (_tool ==
                                                                  _ToolType
                                                                      .text) {
                                                                _textToolPointerDown(
                                                                  e,
                                                                  canvasSize,
                                                                );
                                                              } else {
                                                                _startStroke(
                                                                  e,
                                                                  canvasSize,
                                                                );
                                                              }
                                                            },
                                                            onPointerMove: (e) =>
                                                                _appendStroke(
                                                                  e,
                                                                  canvasSize,
                                                                ),
                                                            onPointerUp:
                                                                _endStroke,
                                                            onPointerCancel:
                                                                _cancelStroke,
                                                            child: Stack(
                                                              fit: StackFit
                                                                  .expand,
                                                              children: [
                                                                RepaintBoundary(
                                                                  child: ListenableBuilder(
                                                                    listenable:
                                                                        _transformController,
                                                                    builder: (context, _) {
                                                                      return CustomPaint(
                                                                        painter: _MemoBackgroundPainter(
                                                                          paperStyle:
                                                                              _paperStyle,
                                                                          hasPdf:
                                                                              hasRasterBackground,
                                                                        ),
                                                                        child:
                                                                            const SizedBox.expand(),
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                                RepaintBoundary(
                                                                  child: ListenableBuilder(
                                                                    listenable: Listenable.merge([
                                                                      _transformController,
                                                                      _annotationRepaint,
                                                                      _debugPointerRepaint,
                                                                    ]),
                                                                    builder: (context, _) {
                                                                      return Stack(
                                                                        fit: StackFit
                                                                            .expand,
                                                                        children: [
                                                                          CustomPaint(
                                                                            painter: _StrokeAnnotationPainter(
                                                                              strokes:
                                                                                  page?.strokes ??
                                                                                  const [],
                                                                              workingStroke: _annotationWorkingPreview(),
                                                                            ),
                                                                            child:
                                                                                const SizedBox.expand(),
                                                                          ),
                                                                          if (kDebugMode)
                                                                            CustomPaint(
                                                                              painter: _TouchAlignmentDebugPainter(
                                                                                touchDoc: _debugTouchDoc,
                                                                                appliedDoc: _debugAppliedDoc,
                                                                              ),
                                                                              child: const SizedBox.expand(),
                                                                            ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                                IgnorePointer(
                                                                  child: ListenableBuilder(
                                                                    listenable: Listenable.merge([
                                                                      _transformController,
                                                                      _laserRepaint,
                                                                    ]),
                                                                    builder: (context, _) {
                                                                      return CustomPaint(
                                                                        painter: _LaserOverlayPainter(
                                                                          modeIndex: _settingsFor(
                                                                            _ToolType.laser,
                                                                          ).laserModeIndex,
                                                                          trailPoints:
                                                                              List<
                                                                                Offset
                                                                              >.from(
                                                                                _laserTrail,
                                                                              ),
                                                                          dotDoc:
                                                                              _laserDotDoc,
                                                                          color:
                                                                              _activeStrokeColor,
                                                                          trailStrokeWidth:
                                                                              _effectiveWidth,
                                                                          trailOpacity:
                                                                              _laserTrailOpacity,
                                                                          repaintVersion:
                                                                              _laserRepaint.value,
                                                                        ),
                                                                        child:
                                                                            const SizedBox.expand(),
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                                RepaintBoundary(
                                                                  child: ListenableBuilder(
                                                                    listenable:
                                                                        _transformController,
                                                                    builder: (context, _) {
                                                                      return Stack(
                                                                        fit: StackFit
                                                                            .expand,
                                                                        children: [
                                                                          ...sortedImages.map((
                                                                            img,
                                                                          ) {
                                                                            final r = img.rect.toLocalRect(
                                                                              canvasSize,
                                                                            );
                                                                            final cacheW =
                                                                                (r.width *
                                                                                        imageDpr)
                                                                                    .round()
                                                                                    .clamp(
                                                                                      1,
                                                                                      4096,
                                                                                    );
                                                                            final cacheH =
                                                                                (r.height *
                                                                                        imageDpr)
                                                                                    .round()
                                                                                    .clamp(
                                                                                      1,
                                                                                      4096,
                                                                                    );
                                                                            return Positioned(
                                                                              left: r.left,
                                                                              top: r.top,
                                                                              width: r.width,
                                                                              height: r.height,
                                                                              child: IgnorePointer(
                                                                                ignoring:
                                                                                    _tool !=
                                                                                    _ToolType.lasso,
                                                                                child: Transform.rotate(
                                                                                  angle: img.rotationRad,
                                                                                  alignment: Alignment.center,
                                                                                  child: Image.file(
                                                                                    File(
                                                                                      img.storagePath,
                                                                                    ),
                                                                                    fit: BoxFit.contain,
                                                                                    cacheWidth: cacheW,
                                                                                    cacheHeight: cacheH,
                                                                                    filterQuality: FilterQuality.medium,
                                                                                    errorBuilder:
                                                                                        (
                                                                                          context,
                                                                                          error,
                                                                                          stackTrace,
                                                                                        ) => const Icon(
                                                                                          Icons.broken_image_outlined,
                                                                                          color: Colors.white54,
                                                                                        ),
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            );
                                                                          }),
                                                                          IgnorePointer(
                                                                            ignoring:
                                                                                true,
                                                                            child: CustomPaint(
                                                                              painter: _StudioOverlayPainter(
                                                                                lassoPath:
                                                                                    _tool ==
                                                                                        _ToolType.lasso
                                                                                    ? (_lassoPathLocal ==
                                                                                              null
                                                                                          ? null
                                                                                          : List<
                                                                                              Offset
                                                                                            >.from(
                                                                                              _lassoPathLocal!,
                                                                                            ))
                                                                                    : null,
                                                                                selectionBounds:
                                                                                    _tool ==
                                                                                        _ToolType.lasso
                                                                                    ? _selectionBoundsLocal(
                                                                                        canvasSize,
                                                                                      )
                                                                                    : null,
                                                                                selectionRotationRad:
                                                                                    _tool ==
                                                                                        _ToolType.lasso
                                                                                    ? _selRotationRad
                                                                                    : 0,
                                                                                showResizeHandles:
                                                                                    _tool ==
                                                                                        _ToolType.lasso &&
                                                                                    _hasLassoSelection &&
                                                                                    _canResizeSelection(),
                                                                              ),
                                                                              child: const SizedBox.expand(),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      );
                                                                    },
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          if (page != null)
                                                            IgnorePointer(
                                                              ignoring:
                                                                  !_textCanvasLayerAbsorbsPointers,
                                                              child: ListenableBuilder(
                                                                listenable:
                                                                    Listenable.merge([
                                                                      _textLayerRepaint,
                                                                    ]),
                                                                builder: (context, _) {
                                                                  return Stack(
                                                                    fit: StackFit
                                                                        .expand,
                                                                    children: [
                                                                      for (final t
                                                                          in page
                                                                              .textBoxes)
                                                                        _canvasMemoTextBox(
                                                                          t,
                                                                          canvasSize,
                                                                        ),
                                                                    ],
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                        ],
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
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
