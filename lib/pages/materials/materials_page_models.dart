part of 'materials_page.dart';

String _mpString(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int _mpInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _mpDouble(Map<String, dynamic> json, String key, [double fallback = 0]) {
  final value = json[key];
  double? parsed;
  if (value is num) parsed = value.toDouble();
  if (value is String) parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) return fallback;
  return parsed;
}

Color _mpColor(dynamic value, Color fallback) {
  final raw = value is int
      ? value
      : (value is num ? value.toInt() : int.tryParse(value?.toString() ?? ''));
  if (raw == null) return fallback;
  return Color(raw);
}

enum _PaperStyle { plain, ruled, grid }

const _memoPaperColor = Color(0xFF2B3038);
const _memoRuleColor = Color(0xFF424A55);
const _memoMarginColor = Color(0xFF6A4650);
const _memoDefaultInkColor = Color(0xFFF4F7FB);
const _defaultColorPalette = [
  Color(0xFFF4F7FB),
  Color(0xFF111827),
  Color(0xFF9CA3AF),
  Color(0xFFE11D48),
  Color(0xFFF97316),
  Color(0xFFFACC15),
  Color(0xFF22C55E),
  Color(0xFF34D399),
  Color(0xFF38BDF8),
  Color(0xFF2563EB),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

/// `text` stays at index 6 for saved stroke `tool` indices; `laser` is presentation-only (index 7).
enum _ToolType { hand, pen, pencil, highlighter, eraser, lasso, text, laser }

/// Strokes that are stored on the page and participate in undo / JSON.
bool _strokeToolIsPersistedInk(_ToolType t) =>
    t != _ToolType.eraser && t != _ToolType.laser;

enum _EraserMode { pixel, stroke }

enum _LassoDragKind { idle, marquee, move, resize, rotate }

int _normalizeLaserDismissMs(int ms) {
  if (ms <= 550) return 500;
  if (ms >= 950) return 1000;
  return 800;
}

/// Sentinel for unified undo (one marker per committed stroke).
class _StrokeUndoMarker {}

/// Full stroke list snapshot for undo (pixel eraser, stroke eraser, etc.).
class _StrokeListSnapshotUndo {
  final List<Map<String, dynamic>> strokesJson;

  const _StrokeListSnapshotUndo({required this.strokesJson});

  factory _StrokeListSnapshotUndo.fromStrokes(List<_Stroke> strokes) {
    return _StrokeListSnapshotUndo(
      strokesJson: strokes
          .where((s) => s.tool != _ToolType.eraser)
          .map((s) => s.toJson())
          .toList(),
    );
  }
}

/// Redo payload after restoring a [_StrokeListSnapshotUndo].
class _StrokeListRedoEntry {
  final List<Map<String, dynamic>> afterJson;

  const _StrokeListRedoEntry({required this.afterJson});

  Map<String, dynamic> toJson() => {
    'kind': 'strokeListRedo',
    'list': afterJson,
  };

  factory _StrokeListRedoEntry.fromJson(Map<String, dynamic> m) {
    final list = m['list'] as List<dynamic>? ?? const [];
    return _StrokeListRedoEntry(
      afterJson: list.whereType<Map<String, dynamic>>().toList(),
    );
  }
}

/// Snapshot of layout-affecting edits (lasso move / resize) for undo.
class _LassoLayoutSnapshot {
  final Map<String, List<Offset>> strokePoints;
  final Map<String, _NormRect> imageRects;
  final Map<String, _NormRect> textRects;
  final Map<String, String> textBodies;
  final Map<String, double> textRotationDeg;
  final Map<String, double> imageRotationDeg;

  /// When set, replaces [page.textBoxes] entirely (create / delete / style batch).
  final List<Map<String, dynamic>>? fullTextBoxesJson;

  _LassoLayoutSnapshot({
    required this.strokePoints,
    required this.imageRects,
    required this.textRects,
    required this.textBodies,
    this.textRotationDeg = const {},
    this.imageRotationDeg = const {},
    this.fullTextBoxesJson,
  });
}

void _applyLassoLayoutSnapshot(_CanvasPage page, _LassoLayoutSnapshot s) {
  if (s.fullTextBoxesJson != null) {
    page.textBoxes
      ..clear()
      ..addAll(
        s.fullTextBoxesJson!
            .map((m) => _CanvasTextBox.fromJson(m, pageId: page.id))
            .toList(),
      );
  } else {
    for (final e in s.textRects.entries) {
      for (final t in page.textBoxes) {
        if (t.id != e.key) continue;
        t.rect
          ..left = e.value.left
          ..top = e.value.top
          ..width = e.value.width
          ..height = e.value.height;
        final body = s.textBodies[e.key];
        if (body != null) t.text = body;
        final rot = s.textRotationDeg[e.key];
        if (rot != null) t.rotationDeg = rot;
        break;
      }
    }
  }
  for (final e in s.strokePoints.entries) {
    for (final st in page.strokes) {
      if (st.id != e.key) continue;
      final pts = e.value;
      final n = math.min(st.points.length, pts.length);
      for (var i = 0; i < n; i++) {
        st.points[i] = pts[i];
      }
      break;
    }
  }
  for (final e in s.imageRects.entries) {
    for (final img in page.placedImages) {
      if (img.id != e.key) continue;
      img.rect
        ..left = e.value.left
        ..top = e.value.top
        ..width = e.value.width
        ..height = e.value.height;
      break;
    }
  }
  for (final e in s.imageRotationDeg.entries) {
    for (final img in page.placedImages) {
      if (img.id != e.key) continue;
      img.rotationDeg = e.value;
      break;
    }
  }
}

/// Captures current page geometry for the same keys as [template] (redo mirror).
_LassoLayoutSnapshot _captureLayoutRedoMirror(
  _CanvasPage page,
  _LassoLayoutSnapshot template,
) {
  if (template.fullTextBoxesJson != null) {
    return _LassoLayoutSnapshot(
      strokePoints: {},
      imageRects: {},
      textRects: {},
      textBodies: {},
      fullTextBoxesJson: page.textBoxes
          .map((t) => t.toJson(emitPageId: page.id))
          .toList(),
    );
  }

  final strokeSnap = <String, List<Offset>>{};
  for (final id in template.strokePoints.keys) {
    for (final s in page.strokes) {
      if (s.id != id) continue;
      strokeSnap[id] = s.points.map((e) => Offset(e.dx, e.dy)).toList();
      break;
    }
  }

  final imgIds = <String>{
    ...template.imageRects.keys,
    ...template.imageRotationDeg.keys,
  };
  final imgSnap = <String, _NormRect>{};
  final imgRot = <String, double>{};
  for (final id in imgIds) {
    for (final img in page.placedImages) {
      if (img.id != id) continue;
      imgSnap[id] = img.rect.copy();
      imgRot[id] = img.rotationDeg;
      break;
    }
  }

  final textIds = <String>{
    ...template.textRects.keys,
    ...template.textRotationDeg.keys,
  };
  final textSnap = <String, _NormRect>{};
  final textBodies = <String, String>{};
  final textRot = <String, double>{};
  for (final id in textIds) {
    for (final t in page.textBoxes) {
      if (t.id != id) continue;
      textSnap[id] = t.rect.copy();
      textBodies[id] = t.text;
      textRot[id] = t.rotationDeg;
      break;
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

/// Full strokes / images / text for bulk restore (e.g. lasso delete).
class _PageVisualStateSnapshot {
  final List<Map<String, dynamic>> strokesJson;
  final List<Map<String, dynamic>> placedImagesJson;
  final List<Map<String, dynamic>> textBoxesJson;

  _PageVisualStateSnapshot._({
    required this.strokesJson,
    required this.placedImagesJson,
    required this.textBoxesJson,
  });

  factory _PageVisualStateSnapshot.fromPage(_CanvasPage page) {
    return _PageVisualStateSnapshot._(
      strokesJson: page.strokes
          .where((s) => _strokeToolIsPersistedInk(s.tool))
          .map((s) => s.toJson())
          .toList(),
      placedImagesJson: page.placedImages.map((e) => e.toJson()).toList(),
      textBoxesJson: page.textBoxes
          .map((e) => e.toJson(emitPageId: page.id))
          .toList(),
    );
  }

  void applyTo(_CanvasPage page) {
    page.strokes
      ..clear()
      ..addAll(
        strokesJson
            .map(_Stroke.fromJson)
            .where((s) => _strokeToolIsPersistedInk(s.tool)),
      );
    page.placedImages
      ..clear()
      ..addAll(placedImagesJson.map(_PlacedImage.fromJson));
    page.textBoxes
      ..clear()
      ..addAll(
        textBoxesJson.map((m) => _CanvasTextBox.fromJson(m, pageId: page.id)),
      );
  }
}

/// Canvas page background / render source (memo vs PDF vs full-page image).
enum _CanvasPageKind { memo, pdf, importedImage }

/// How PDF pages are fitted into the memo (√2) aspect frame.
enum _PdfDisplayMode { preservePdfAspect, stretchToMemo }

extension _ToolTypeUi on _ToolType {
  String get label {
    switch (this) {
      case _ToolType.hand:
        return '이동';
      case _ToolType.pen:
        return '펜';
      case _ToolType.pencil:
        return '연필';
      case _ToolType.highlighter:
        return '형광펜';
      case _ToolType.eraser:
        return '지우개';
      case _ToolType.lasso:
        return '올가미';
      case _ToolType.text:
        return '텍스트';
      case _ToolType.laser:
        return '레이저';
    }
  }
}

class _ToolSettings {
  Color color;
  double width;
  double opacity;
  bool bold;
  bool italic;

  /// Default font family for new text objects; empty = system UI font.
  String textFontFamily;
  bool textUnderline;

  /// 0 = start, 1 = center, 2 = end (maps to [TextAlign]).
  int textAlignIndex;

  /// Used when creating a new [_CanvasTextBox] if no box is targeted in the UI.
  bool textBoxNextHasBackground;
  Color textBoxNextBackgroundColor;
  bool textBoxNextHasBorder;
  Color textBoxNextBorderColor;

  /// 0 = dot, 1 = trail (ephemeral laser overlay).
  int laserModeIndex;

  /// Trail hold + fade total target (ms); normalized in UI to 500 / 800 / 1000.
  int laserDismissMs;

  _ToolSettings({
    required this.color,
    required this.width,
    required this.opacity,
    this.bold = false,
    this.italic = false,
    this.textFontFamily = '',
    this.textUnderline = false,
    this.textAlignIndex = 0,
    this.textBoxNextHasBackground = false,
    this.textBoxNextBackgroundColor = const Color(0x66FACC15),
    this.textBoxNextHasBorder = false,
    this.textBoxNextBorderColor = const Color(0xFF6B7280),
    this.laserModeIndex = 1,
    this.laserDismissMs = 800,
  });

  Map<String, dynamic> toJson() => {
    'color': color.toARGB32(),
    'width': width,
    'opacity': opacity,
    'bold': bold,
    'italic': italic,
    'textFontFamily': textFontFamily,
    'textUnderline': textUnderline,
    'textAlignIndex': textAlignIndex,
    'textBoxNextHasBackground': textBoxNextHasBackground,
    'textBoxNextBackgroundColor': textBoxNextBackgroundColor.toARGB32(),
    'textBoxNextHasBorder': textBoxNextHasBorder,
    'textBoxNextBorderColor': textBoxNextBorderColor.toARGB32(),
    'laserModeIndex': laserModeIndex,
    'laserDismissMs': laserDismissMs,
  };

  factory _ToolSettings.fromJson(
    Map<String, dynamic> json, {
    required _ToolSettings fallback,
  }) {
    final s = _ToolSettings(
      color: _mpColor(json['color'], fallback.color),
      width: _mpDouble(json, 'width', fallback.width),
      opacity: _mpDouble(json, 'opacity', fallback.opacity),
      bold: json['bold'] as bool? ?? fallback.bold,
      italic: json['italic'] as bool? ?? fallback.italic,
      textFontFamily: _mpString(
        json,
        'textFontFamily',
        fallback.textFontFamily,
      ),
      textUnderline: json['textUnderline'] as bool? ?? fallback.textUnderline,
      textAlignIndex: _mpInt(json, 'textAlignIndex', fallback.textAlignIndex),
      textBoxNextHasBackground:
          json['textBoxNextHasBackground'] as bool? ??
          fallback.textBoxNextHasBackground,
      textBoxNextBackgroundColor: _mpColor(
        json['textBoxNextBackgroundColor'],
        fallback.textBoxNextBackgroundColor,
      ),
      textBoxNextHasBorder:
          json['textBoxNextHasBorder'] as bool? ??
          fallback.textBoxNextHasBorder,
      textBoxNextBorderColor: _mpColor(
        json['textBoxNextBorderColor'],
        fallback.textBoxNextBorderColor,
      ),
      laserModeIndex: fallback.laserModeIndex,
      laserDismissMs: fallback.laserDismissMs,
    );
    s.laserModeIndex = _mpInt(
      json,
      'laserModeIndex',
      fallback.laserModeIndex,
    ).clamp(0, 1);
    s.laserDismissMs = _normalizeLaserDismissMs(
      _mpInt(json, 'laserDismissMs', fallback.laserDismissMs),
    );
    return s;
  }
}

// ── DATA MODELS ──────────────────────────────────────────────────

class _Folder {
  final String id;
  String name;
  final Color color;
  bool isExpanded;

  _Folder({
    required this.id,
    required this.name,
    required this.color,
    this.isExpanded = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'isExpanded': isExpanded,
  };

  factory _Folder.fromJson(Map<String, dynamic> json) => _Folder(
    id: _mpString(json, 'id'),
    name: _mpString(json, 'name'),
    color: _mpColor(json['color'], const Color(0xFF4DA3FF)),
    isExpanded: json['isExpanded'] as bool? ?? true,
  );
}

class _Memo {
  final String id;
  String name;
  final String folderId;
  final List<_CanvasPage> pages;
  String? pdfId;
  _PdfDisplayMode pdfDisplayMode;

  _Memo({
    required this.id,
    required this.name,
    required this.folderId,
    List<_CanvasPage>? pages,
    this.pdfId,
    this.pdfDisplayMode = _PdfDisplayMode.preservePdfAspect,
  }) : pages = pages ?? [_CanvasPage.createDefaultMemoPage()];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'folderId': folderId,
    'pdfId': pdfId,
    'pdfDisplayMode': pdfDisplayMode.index,
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory _Memo.fromJson(Map<String, dynamic> json) {
    final pagesJson = json['pages'] as List<dynamic>? ?? const [];
    final memoPdfId = json['pdfId']?.toString();
    final memoLegacyCanvasRot = _mpInt(
      json,
      'canvasRotationQuarterTurns',
      0,
    ).clamp(0, 3);
    final pages = <_CanvasPage>[];
    for (final item in pagesJson) {
      if (item is! Map) continue;
      try {
        pages.add(
          _CanvasPage.fromJson(
            Map<String, dynamic>.from(item),
            legacyMemoPdfId: memoPdfId,
            memoLegacyCanvasRotation: memoLegacyCanvasRot,
          ),
        );
      } catch (_) {}
    }
    final rawMode =
        json['pdfDisplayMode'] as int? ??
        _PdfDisplayMode.preservePdfAspect.index;
    final modeIdx = rawMode.clamp(0, _PdfDisplayMode.values.length - 1);
    return _Memo(
      id: _mpString(json, 'id'),
      name: _mpString(json, 'name'),
      folderId: _mpString(json, 'folderId'),
      pdfId: json['pdfId']?.toString(),
      pdfDisplayMode: _PdfDisplayMode.values[modeIdx],
      pages: pages.isEmpty ? [_CanvasPage.createDefaultMemoPage()] : pages,
    );
  }
}

/// Normalized rectangle (0–1) relative to the memo canvas.
class _NormRect {
  double left;
  double top;
  double width;
  double height;

  _NormRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Rect toLocalRect(Size canvas) => Rect.fromLTWH(
    left * canvas.width,
    top * canvas.height,
    width * canvas.width,
    height * canvas.height,
  );

  Map<String, dynamic> toJson() => {
    'l': left,
    't': top,
    'w': width,
    'h': height,
  };

  factory _NormRect.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return _NormRect(left: 0.1, top: 0.1, width: 0.4, height: 0.2);
    }
    return _NormRect(
      left: _mpDouble(json, 'l', 0.1).clamp(0.0, 1.0),
      top: _mpDouble(json, 't', 0.1).clamp(0.0, 1.0),
      width: _mpDouble(json, 'w', 0.4).clamp(0.02, 1.0),
      height: _mpDouble(json, 'h', 0.2).clamp(0.02, 1.0),
    );
  }

  _NormRect copy() =>
      _NormRect(left: left, top: top, width: width, height: height);

  /// Builds normalized rect from a canvas-space [Rect].
  factory _NormRect.fromLocalRect(Rect r, Size canvas) {
    final w = canvas.width;
    final h = canvas.height;
    if (w <= 0 || h <= 0) {
      return _NormRect(left: 0.1, top: 0.1, width: 0.34, height: 0.08);
    }
    var nl = (r.left / w).clamp(0.0, 1.0);
    var nt = (r.top / h).clamp(0.0, 1.0);
    var nw = (r.width / w).clamp(0.02, 1.0);
    var nh = (r.height / h).clamp(0.02, 1.0);
    if (nl + nw > 1.0) nw = (1.0 - nl).clamp(0.02, 1.0);
    if (nt + nh > 1.0) nh = (1.0 - nt).clamp(0.02, 1.0);
    return _NormRect(left: nl, top: nt, width: nw, height: nh);
  }
}

class _PlacedImage {
  final String id;
  String storagePath;
  _NormRect rect;

  /// Reserved for future z-order / rotation.
  int zIndex;
  double rotationDeg;

  _PlacedImage({
    required this.id,
    required this.storagePath,
    required this.rect,
    this.zIndex = 0,
    this.rotationDeg = 0,
  });

  double get rotationRad => rotationDeg * math.pi / 180;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': storagePath,
    'rect': rect.toJson(),
    'z': zIndex,
    'rotationDeg': rotationDeg,
  };

  factory _PlacedImage.fromJson(Map<String, dynamic> json) => _PlacedImage(
    id: _mpString(json, 'id'),
    storagePath: _mpString(json, 'path'),
    rect: _NormRect.fromJson(json['rect'] as Map<String, dynamic>?),
    zIndex: _mpInt(json, 'z', 0),
    rotationDeg: _mpDouble(json, 'rotationDeg', 0),
  );
}

/// Canvas text object (GoodNotes-style), stored separately from strokes.
/// v1: one plain [text] string plus box-level typography and decoration only.
///
/// Future: optional `runs` / `spans` (or similar) may be added to JSON for rich text
/// without removing existing keys; clients should keep treating unknown keys leniently.
class _CanvasTextBox {
  final String id;
  String? pageId;
  String text;
  _NormRect rect;
  double rotationDeg;
  String fontFamily;
  double fontSize;
  bool bold;
  bool italic;
  bool underline;
  Color color;
  Color backgroundColor;
  bool hasBackground;
  Color borderColor;
  bool hasBorder;

  /// 0 = start, 1 = center, 2 = end.
  int textAlignIndex;

  /// When `true`, the box auto-fits its width+height to follow typed
  /// content (Goodnotes-style "grow with text"). Flips to `false` the
  /// moment the user manually drags a resize handle so subsequent typing
  /// only grows the box vertically inside the user-chosen width.
  ///
  /// Defaults to `true` for new boxes; legacy JSON without this key is
  /// also treated as auto-size for backward compatibility.
  bool autoSize;
  int createdAtMillis;
  int updatedAtMillis;

  _CanvasTextBox({
    required this.id,
    this.pageId,
    required this.text,
    required this.rect,
    this.rotationDeg = 0,
    this.fontFamily = '',
    this.fontSize = 16,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = _memoDefaultInkColor,
    this.backgroundColor = const Color(0x00000000),
    this.hasBackground = false,
    this.borderColor = const Color(0xFF6B7280),
    this.hasBorder = false,
    this.textAlignIndex = 0,
    this.autoSize = true,
    int? createdAtMillis,
    int? updatedAtMillis,
  }) : createdAtMillis =
           createdAtMillis ?? DateTime.now().millisecondsSinceEpoch,
       updatedAtMillis =
           updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;

  double get rotationRad => rotationDeg * math.pi / 180;

  set rotationRad(double r) {
    rotationDeg = r * 180 / math.pi;
  }

  TextAlign get textAlign {
    switch (textAlignIndex.clamp(0, 2)) {
      case 1:
        return TextAlign.center;
      case 2:
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  void markUpdated() {
    updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson({String? emitPageId}) {
    final pid = emitPageId ?? pageId;
    return {
      'id': id,
      'pageId': pid,
      'text': text,
      'rect': rect.toJson(),
      'rotationDeg': rotationDeg,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'bold': bold,
      'italic': italic,
      'underline': underline,
      'color': color.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'hasBackground': hasBackground,
      'borderColor': borderColor.toARGB32(),
      'hasBorder': hasBorder,
      'textAlignIndex': textAlignIndex,
      'autoSize': autoSize,
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory _CanvasTextBox.fromJson(Map<String, dynamic> json, {String? pageId}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _CanvasTextBox(
      id: _mpString(json, 'id'),
      pageId: json['pageId']?.toString() ?? pageId,
      text: _mpString(json, 'text'),
      rect: _NormRect.fromJson(json['rect'] as Map<String, dynamic>?),
      rotationDeg: _mpDouble(json, 'rotationDeg', 0),
      fontFamily: _mpString(json, 'fontFamily'),
      fontSize: _mpDouble(json, 'fontSize', 16).clamp(8.0, 240.0),
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      color: _mpColor(json['color'], _memoDefaultInkColor),
      backgroundColor: _mpColor(
        json['backgroundColor'],
        const Color(0x00000000),
      ),
      hasBackground: json['hasBackground'] as bool? ?? false,
      borderColor: _mpColor(json['borderColor'], const Color(0xFF6B7280)),
      hasBorder: json['hasBorder'] as bool? ?? false,
      textAlignIndex: _mpInt(json, 'textAlignIndex', 0),
      // Legacy boxes (pre-autoSize) defaulted to user-controlled size; keep
      // them in manual mode so we don't silently resize them on load.
      autoSize: json['autoSize'] as bool? ?? false,
      createdAtMillis: _mpInt(json, 'createdAtMillis', now),
      updatedAtMillis: _mpInt(json, 'updatedAtMillis', now),
    );
  }
}
