part of 'materials_page.dart';

const double _kTextHandleHit = 26;

TextStyle _canvasTextBoxTextStyle(_CanvasTextBox box) {
  return TextStyle(
    fontFamily: box.fontFamily.isEmpty ? null : box.fontFamily,
    fontSize: box.fontSize,
    fontWeight: box.bold ? FontWeight.w800 : FontWeight.w500,
    fontStyle: box.italic ? FontStyle.italic : FontStyle.normal,
    decoration: box.underline ? TextDecoration.underline : TextDecoration.none,
    color: box.color,
    height: _kCanvasTextLineHeight,
  );
}

StrutStyle _canvasTextBoxStrutStyle(_CanvasTextBox box) {
  return StrutStyle(
    fontSize: box.fontSize,
    height: _kCanvasTextLineHeight,
    fontFamily: box.fontFamily.isEmpty ? null : box.fontFamily,
    fontWeight: box.bold ? FontWeight.w800 : FontWeight.w500,
    forceStrutHeight: false,
  );
}

/// Canvas text object: rectangular selection, shared handle style with lasso.
class _CanvasTextObjectView extends StatefulWidget {
  final _CanvasTextBox box;
  final Size canvasSize;
  final bool textToolActive;
  final bool selected;
  final bool editing;
  final TextEditingController? editController;
  final FocusNode editFocus;

  const _CanvasTextObjectView({
    required this.box,
    required this.canvasSize,
    required this.textToolActive,
    required this.selected,
    required this.editing,
    required this.editController,
    required this.editFocus,
  });

  @override
  State<_CanvasTextObjectView> createState() => _CanvasTextObjectViewState();
}

class _CanvasTextObjectViewState extends State<_CanvasTextObjectView> {
  _MaterialsPageState? get _pageState =>
      context.findAncestorStateOfType<_MaterialsPageState>();

  int? _textDragPointerId;
  double? _rotatePanStartRad;
  double? _rotateBoxStartDeg;
  final GlobalKey _rotateLayoutKey = GlobalKey();

  TextStyle get _style {
    return _canvasTextBoxTextStyle(widget.box);
  }

  StrutStyle get _strut {
    return _canvasTextBoxStrutStyle(widget.box);
  }

  Widget _hitChip({
    required Widget child,
    required void Function(DragUpdateDetails d) onPanUpdate,
    void Function(DragStartDetails d)? onPanStart,
    void Function(DragEndDetails d)? onPanEnd,
  }) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: _kTextHandleHit,
        height: _kTextHandleHit,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _resizeDot(int handle) {
    return _hitChip(
      child: Container(
        width: _studioSelHandle,
        height: _studioSelHandle,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _kLassoHandleBorder, width: 1.2),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      onPanStart: (_) {
        _pageState?._beginCanvasTextResizeUndo(widget.box.id);
      },
      onPanUpdate: (d) {
        _pageState?._applyCanvasTextResizeHandle(
          widget.box.id,
          handle,
          d.delta,
          widget.canvasSize,
        );
      },
      onPanEnd: (_) {
        _pageState?._endCanvasTextResizeUndo();
      },
    );
  }

  Widget _rotateChip({
    required double topEx,
    required double boxW,
    required double boxH,
  }) {
    final pivotLocal = Offset(boxW * 0.5, topEx + boxH * 0.5);
    return _hitChip(
      child: Container(
        width: _studioSelRotateR * 2,
        height: _studioSelRotateR * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _kLassoAccent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Text(
          '↻',
          style: TextStyle(
            color: Colors.white,
            fontSize: _studioSelRotateR * 1.05,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
      onPanStart: (d) {
        _pageState?._beginCanvasTextRotateUndo(widget.box.id);
        final renderObject =
            _rotateLayoutKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderObject == null) return;
        final c = renderObject.localToGlobal(pivotLocal);
        _rotatePanStartRad = math.atan2(
          d.globalPosition.dy - c.dy,
          d.globalPosition.dx - c.dx,
        );
        _rotateBoxStartDeg = widget.box.rotationDeg;
      },
      onPanUpdate: (d) {
        final startA = _rotatePanStartRad;
        final startDeg = _rotateBoxStartDeg;
        final page = _pageState;
        if (startA == null || startDeg == null || page == null) return;
        final renderObject =
            _rotateLayoutKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderObject == null) return;
        final c = renderObject.localToGlobal(pivotLocal);
        final ang = math.atan2(
          d.globalPosition.dy - c.dy,
          d.globalPosition.dx - c.dx,
        );
        final dRad = _unwrapAngleDelta(ang - startA);
        page._setCanvasTextRotationWhileDragging(
          widget.box.id,
          startDeg + dRad * 180 / math.pi,
        );
      },
      onPanEnd: (_) {
        _rotatePanStartRad = null;
        _rotateBoxStartDeg = null;
        _pageState?._endCanvasTextRotateUndo();
      },
    );
  }

  Widget _miniFab({
    required String glyph,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: _studioSelFabSize,
          height: _studioSelFabSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xD9161820),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Text(
            glyph,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.box;
    final r = t.rect.toLocalRect(widget.canvasSize);
    final st = _pageState;
    final showChrome = widget.textToolActive && widget.selected;
    final bw = r.width;
    final bh = r.height;
    final topEx = showChrome
        ? _studioSelRotateGap + _studioSelRotateR * 2 + _kTextHandleHit * 0.5
        : 0.0;
    final botEx = showChrome ? _studioSelBarPad + _studioSelFabSize + 10 : 0.0;
    final sideEx = showChrome
        ? math.max(
            _kTextHandleHit * 0.5,
            math.max(
              0.0,
              (_studioSelFabSize * 2 + _studioSelFabGap - bw) * 0.5 + 2,
            ),
          )
        : 0.0;
    final fabTop = topEx + bh + _studioSelBarPad;

    final boxDecoration = BoxDecoration(
      color: t.hasBackground ? t.backgroundColor : null,
      border: t.hasBorder
          ? Border.all(color: t.borderColor, width: 1.05)
          : (showChrome
                ? Border.all(
                    color: _kLassoAccent.withValues(alpha: 0.95),
                    width: 1.25,
                  )
                : null),
      borderRadius: BorderRadius.zero,
    );

    final content = widget.editing && widget.editController != null
        ? TextField(
            key: ValueKey('tf-${t.id}'),
            controller: widget.editController,
            focusNode: widget.editFocus,
            minLines: 1,
            maxLines: null,
            expands: false,
            textAlign: t.textAlign,
            textAlignVertical: TextAlignVertical.top,
            style: _style,
            strutStyle: _strut,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            magnifierConfiguration: TextMagnifierConfiguration.disabled,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              hoverColor: Colors.transparent,
              fillColor: Colors.transparent,
              filled: false,
              isDense: true,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            cursorWidth: 1.6,
            cursorColor: t.color,
            scrollPadding: EdgeInsets.zero,
            keyboardAppearance: Brightness.light,
            onSubmitted: (_) => st?._finishInlineTextEdit(),
          )
        : Text(
            t.text.isEmpty ? ' ' : t.text,
            textAlign: t.textAlign,
            style: _style,
            strutStyle: _strut,
          );

    final copyRect = _studioSelectionCopyFabRect(r);
    final delRect = _studioSelectionDeleteFabRect(r);

    return Positioned(
      left: r.left - sideEx,
      top: r.top - topEx,
      width: bw + sideEx * 2,
      height: topEx + bh + botEx,
      child: IgnorePointer(
        ignoring: !widget.textToolActive,
        child: Transform.rotate(
          angle: t.rotationRad,
          origin: Offset(bw * 0.5, topEx + bh * 0.5),
          child: Stack(
            key: _rotateLayoutKey,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: topEx,
                left: sideEx,
                width: bw,
                height: bh,
                child: DecoratedBox(
                  decoration: boxDecoration,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kTextInlineHorizontalPadding,
                      vertical: _kTextInlineVerticalPadding,
                    ),
                    child: widget.editing
                        ? content
                        : Listener(
                            behavior:
                                widget.textToolActive &&
                                    widget.selected &&
                                    !widget.editing
                                ? HitTestBehavior.opaque
                                : HitTestBehavior.deferToChild,
                            onPointerDown: (e) {
                              if (!widget.textToolActive || widget.editing) {
                                return;
                              }
                              if (widget.selected) {
                                _textDragPointerId = e.pointer;
                                _pageState?._beginCanvasTextDragUndo(
                                  widget.box.id,
                                );
                              }
                            },
                            onPointerMove: (e) {
                              if (_textDragPointerId != e.pointer) return;
                              if (!widget.textToolActive ||
                                  !widget.selected ||
                                  widget.editing) {
                                return;
                              }
                              if (!e.down) return;
                              _pageState?._applyCanvasTextMoveByDelta(
                                widget.box.id,
                                e.delta,
                                widget.canvasSize,
                              );
                            },
                            onPointerUp: (e) {
                              if (_textDragPointerId == e.pointer) {
                                _textDragPointerId = null;
                                if (widget.textToolActive &&
                                    widget.selected &&
                                    !widget.editing) {
                                  _pageState?._endCanvasTextDragUndo();
                                }
                              }
                            },
                            onPointerCancel: (e) {
                              if (_textDragPointerId == e.pointer) {
                                _textDragPointerId = null;
                                if (widget.textToolActive &&
                                    widget.selected &&
                                    !widget.editing) {
                                  _pageState?._endCanvasTextDragUndo();
                                }
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (!widget.textToolActive) return;
                                st?._selectCanvasTextSingle(t.id);
                              },
                              onDoubleTap: () {
                                if (!widget.textToolActive) return;
                                st?._selectCanvasTextSingle(t.id);
                                st?._beginInlineTextEdit(t);
                              },
                              child: content,
                            ),
                          ),
                  ),
                ),
              ),
              if (showChrome) ...[
                Positioned(
                  left: sideEx + bw * 0.5 - _kTextHandleHit * 0.5,
                  top: topEx - _studioSelRotateGap - _studioSelRotateR * 2,
                  child: _rotateChip(topEx: topEx, boxW: bw, boxH: bh),
                ),
                Positioned(
                  left: sideEx - _kTextHandleHit * 0.5,
                  top: topEx - _kTextHandleHit * 0.5,
                  child: _resizeDot(0),
                ),
                Positioned(
                  left: sideEx + bw * 0.5 - _kTextHandleHit * 0.5,
                  top: topEx - _kTextHandleHit * 0.5,
                  child: _resizeDot(1),
                ),
                Positioned(
                  left: sideEx + bw - _kTextHandleHit * 0.5,
                  top: topEx - _kTextHandleHit * 0.5,
                  child: _resizeDot(2),
                ),
                Positioned(
                  left: sideEx + bw - _kTextHandleHit * 0.5,
                  top: topEx + bh * 0.5 - _kTextHandleHit * 0.5,
                  child: _resizeDot(3),
                ),
                Positioned(
                  left: sideEx + bw - _kTextHandleHit * 0.5,
                  top: topEx + bh - _kTextHandleHit * 0.5,
                  child: _resizeDot(4),
                ),
                Positioned(
                  left: sideEx + bw * 0.5 - _kTextHandleHit * 0.5,
                  top: topEx + bh - _kTextHandleHit * 0.5,
                  child: _resizeDot(5),
                ),
                Positioned(
                  left: sideEx - _kTextHandleHit * 0.5,
                  top: topEx + bh - _kTextHandleHit * 0.5,
                  child: _resizeDot(6),
                ),
                Positioned(
                  left: sideEx - _kTextHandleHit * 0.5,
                  top: topEx + bh * 0.5 - _kTextHandleHit * 0.5,
                  child: _resizeDot(7),
                ),
                Positioned(
                  left: sideEx + copyRect.left - r.left,
                  top: fabTop,
                  width: _studioSelFabSize,
                  height: _studioSelFabSize,
                  child: _miniFab(
                    glyph: '⎘',
                    color: const Color(0xFF93C5FD),
                    onTap: () =>
                        st?._textDuplicateSelectionNearby(widget.canvasSize),
                  ),
                ),
                Positioned(
                  left: sideEx + delRect.left - r.left,
                  top: fabTop,
                  width: _studioSelFabSize,
                  height: _studioSelFabSize,
                  child: _miniFab(
                    glyph: '×',
                    color: const Color(0xFFF87171),
                    onTap: () => st?._textToolbarDeleteSelection(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
