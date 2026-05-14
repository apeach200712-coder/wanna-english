import 'package:flutter/material.dart';

/// 전화번호용 — 시스템 키보드 대신 3×4 다이얼만 사용합니다.
class DialPadPhoneField extends StatelessWidget {
  const DialPadPhoneField({
    super.key,
    required this.controller,
    required this.decoration,
    this.sheetTitle = '번호 입력',
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final String sheetTitle;

  Future<void> _openDial(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PhoneDialSheet(
        title: sheetTitle,
        initial: controller.text,
        onDone: (value) {
          controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      keyboardType: TextInputType.none,
      enableSuggestions: false,
      autocorrect: false,
      decoration: decoration.copyWith(
        suffixIcon: IconButton(
          tooltip: '다이얼 열기',
          icon: const Icon(Icons.dialpad_rounded),
          onPressed: () => _openDial(context),
        ),
      ),
      onTap: () => _openDial(context),
    );
  }
}

class _PhoneDialSheet extends StatefulWidget {
  const _PhoneDialSheet({
    required this.title,
    required this.initial,
    required this.onDone,
  });

  final String title;
  final String initial;
  final ValueChanged<String> onDone;

  @override
  State<_PhoneDialSheet> createState() => _PhoneDialSheetState();
}

class _PhoneDialSheetState extends State<_PhoneDialSheet> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial.replaceAll(RegExp(r'[^0-9*#]'), '');
  }

  void _append(String ch) {
    setState(() => _value += ch);
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _value.isEmpty ? ' ' : _value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onDone(_value);
                      Navigator.pop(context);
                    },
                    child: const Text('확인'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final row in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: row
                      .map(
                        (k) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _DialKey(
                              label: k,
                              onTap: () => _append(k),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
