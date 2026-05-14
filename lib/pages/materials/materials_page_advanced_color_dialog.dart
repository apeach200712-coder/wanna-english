part of 'materials_page.dart';

class _AdvancedColorResult {
  final Color color;
  final double opacity;

  const _AdvancedColorResult({required this.color, required this.opacity});
}

String _hexFromColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHexColor(String input) {
  final normalized = input.trim().replaceAll('#', '');
  if (normalized.length != 6) return null;
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

class _AdvancedColorDialog extends StatefulWidget {
  final Color initialColor;
  final double initialOpacity;

  /// When false (e.g. 형광펜), opacity is not edited here — width 패널에서 조절.
  final bool editOpacity;

  const _AdvancedColorDialog({
    required this.initialColor,
    required this.initialOpacity,
    this.editOpacity = true,
  });

  @override
  State<_AdvancedColorDialog> createState() => _AdvancedColorDialogState();
}

class _AdvancedColorDialogState extends State<_AdvancedColorDialog> {
  late HSVColor _draft;
  late final TextEditingController _hexController;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _draft = HSVColor.fromColor(
      widget.initialColor.withValues(alpha: widget.initialOpacity),
    );
    _hexController = TextEditingController(
      text: _hexFromColor(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _previewColor => _draft.toColor();

  void _syncHex() {
    final next = _hexFromColor(_previewColor);
    if (_hexController.text != next) {
      _hexController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  void _updateSpectrum(Offset localPosition, Size size) {
    final saturation = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - (localPosition.dy / size.height)).clamp(0.0, 1.0);
    setState(() {
      _draft = _draft.withSaturation(saturation).withValue(value);
      _hexError = null;
      _syncHex();
    });
  }

  void _handleHexChanged(String raw) {
    final parsed = _parseHexColor(raw);
    if (raw.trim().isEmpty) {
      setState(() => _hexError = null);
      return;
    }
    if (parsed == null) {
      setState(() => _hexError = '올바른 색상 코드가 아닙니다');
      return;
    }
    setState(() {
      _draft = HSVColor.fromColor(parsed).withAlpha(_draft.alpha);
      _hexError = null;
      _syncHex();
    });
  }

  Future<void> _promptHueNumeric() async {
    final ctrl = TextEditingController(text: _draft.hue.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('색상 (0–360)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '0 ~ 360',
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
              Navigator.pop(ctx, parsed.clamp(0.0, 360.0));
            },
            child: const Text('적용'),
          ),
        ],
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350), ctrl.dispose),
    );
    if (v == null || !mounted) return;
    setState(() {
      _draft = _draft.withHue(v);
      _hexError = null;
      _syncHex();
    });
  }

  Future<void> _promptSaturationPercent() async {
    final pct = (_draft.saturation * 100).round().clamp(0, 100);
    final ctrl = TextEditingController(text: '$pct');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('채도 (%)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '0 ~ 100',
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
    if (v == null || !mounted) return;
    setState(() {
      _draft = _draft.withSaturation(v / 100.0);
      _hexError = null;
      _syncHex();
    });
  }

  Future<void> _promptValuePercent() async {
    final pct = (_draft.value * 100).round().clamp(0, 100);
    final ctrl = TextEditingController(text: '$pct');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('밝기 (%)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '0 ~ 100',
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
    if (v == null || !mounted) return;
    setState(() {
      _draft = _draft.withValue(v / 100.0);
      _hexError = null;
      _syncHex();
    });
  }

  Future<void> _promptAlphaPercent() async {
    final pct = (_draft.alpha * 100).round().clamp(0, 100);
    final ctrl = TextEditingController(text: '$pct');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('투명도 (%)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '0 ~ 100',
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
    if (v == null || !mounted) return;
    setState(() {
      _draft = _draft.withAlpha(v / 100.0);
      _hexError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _draft.hue, 1, 1).toColor();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
          boxShadow: softShadow(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '고급 색상',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _previewColor,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.line),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.subText),
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ColorSpectrumBox(
              hueColor: hueColor,
              saturation: _draft.saturation,
              value: _draft.value,
              onChanged: _updateSpectrum,
            ),
            const SizedBox(height: 14),
            _ColorSliderRow(
              label: '색상',
              value: _draft.hue,
              min: 0,
              max: 360,
              valueFormatter: (value) => value.round().toString(),
              onValueTap: _promptHueNumeric,
              onChanged: (value) {
                setState(() {
                  _draft = _draft.withHue(value);
                  _hexError = null;
                  _syncHex();
                });
              },
            ),
            _ColorSliderRow(
              label: '채도',
              value: _draft.saturation,
              min: 0,
              max: 1,
              valueFormatter: (value) => '${(value * 100).round()}%',
              onValueTap: _promptSaturationPercent,
              onChanged: (value) {
                setState(() {
                  _draft = _draft.withSaturation(value);
                  _hexError = null;
                  _syncHex();
                });
              },
            ),
            _ColorSliderRow(
              label: '밝기',
              value: _draft.value,
              min: 0,
              max: 1,
              valueFormatter: (value) => '${(value * 100).round()}%',
              onValueTap: _promptValuePercent,
              onChanged: (value) {
                setState(() {
                  _draft = _draft.withValue(value);
                  _hexError = null;
                  _syncHex();
                });
              },
            ),
            if (widget.editOpacity)
              _ColorSliderRow(
                label: '투명도',
                value: _draft.alpha,
                min: 0,
                max: 1,
                valueFormatter: (value) => '${(value * 100).round()}%',
                onValueTap: _promptAlphaPercent,
                onChanged: (value) {
                  setState(() {
                    _draft = _draft.withAlpha(value);
                    _hexError = null;
                  });
                },
              ),
            const SizedBox(height: 8),
            const Text(
              'HEX 색상 코드',
              style: TextStyle(
                color: AppColors.subText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hexController,
              onChanged: _handleHexChanged,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              ],
              decoration: InputDecoration(
                hintText: '#5AA4F5',
                errorText: _hexError,
                helperText: '현재 값 ${_hexFromColor(_previewColor)}',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _AdvancedColorResult(
                          color: _previewColor.withValues(alpha: 1),
                          opacity: widget.editOpacity
                              ? _draft.alpha
                              : widget.initialOpacity,
                        ),
                      );
                    },
                    child: const Text('적용'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSpectrumBox extends StatelessWidget {
  final Color hueColor;
  final double saturation;
  final double value;
  final void Function(Offset localPosition, Size size) onChanged;

  const _ColorSpectrumBox({
    required this.hueColor,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 180);
        final markerOffset = Offset(
          saturation * size.width,
          (1 - value) * size.height,
        );
        return GestureDetector(
          onPanDown: (details) => onChanged(details.localPosition, size),
          onPanUpdate: (details) => onChanged(details.localPosition, size),
          child: Container(
            height: size.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, hueColor],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: markerOffset.dx - 10,
                    top: markerOffset.dy - 10,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: softShadow(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final bool enabled;

  const _ActionBtn({
    required this.icon,
    required this.onTap,
    this.compact = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: compact ? 32 : 34,
            height: compact ? 32 : 34,
            decoration: BoxDecoration(
              color: AppColors.graySoft,
              borderRadius: BorderRadius.circular(10),
              border: compact ? Border.all(color: AppColors.line) : null,
            ),
            child: Icon(icon, size: compact ? 18 : 19, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}

class _MiniIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _MiniIconBtn({required this.icon, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.graySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: AppColors.navy),
          ),
        ),
      ),
    );
  }
}
