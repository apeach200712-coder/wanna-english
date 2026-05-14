import 'package:flutter/foundation.dart';

class ClassSelectionService extends ChangeNotifier {
  String? _selectedClass;

  String? get selectedClass => _selectedClass;

  void selectClass(String? className) {
    final normalized = (className == null || className.trim().isEmpty)
        ? null
        : className.trim();
    if (_selectedClass == normalized) return;
    _selectedClass = normalized;
    notifyListeners();
  }
}
