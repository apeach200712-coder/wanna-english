DateTime nowKst() {
  return DateTime.now().toUtc().add(const Duration(hours: 9));
}

DateTime todayKst() {
  final now = nowKst();
  return DateTime(now.year, now.month, now.day);
}
