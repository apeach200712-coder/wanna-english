/// 나이스(NEIS) 학교종류명 등에서 쓰는 학교급 구분.
enum SchoolSearchTier {
  elementary,
  middle,
  high,
}

List<String> gradesForTier(SchoolSearchTier tier) {
  switch (tier) {
    case SchoolSearchTier.elementary:
      return List<String>.generate(6, (i) => '${i + 1}학년');
    case SchoolSearchTier.middle:
    case SchoolSearchTier.high:
      return const ['1학년', '2학년', '3학년'];
  }
}

int _maxGradeNumber(SchoolSearchTier tier) {
  switch (tier) {
    case SchoolSearchTier.elementary:
      return 6;
    case SchoolSearchTier.middle:
    case SchoolSearchTier.high:
      return 3;
  }
}

/// 저장값이 학교급과 맞는지 검사 (1학년 … 또는 레거시 초1·중2·고3).
bool gradeNumberValidForTier(int n, SchoolSearchTier tier) {
  return n >= 1 && n <= _maxGradeNumber(tier);
}

/// 레거시 `초1`·`고2` 또는 이미 `2학년` 형태 → 해당 급에 맞는 표준 `N학년` (불가면 null).
String? canonicalGradeForTier(String? stored, SchoolSearchTier tier) {
  if (stored == null) return null;
  final t = stored.trim();
  if (t.isEmpty) return null;

  final modern = RegExp(r'^(\d+)학년$').firstMatch(t);
  if (modern != null) {
    final n = int.tryParse(modern.group(1)!) ?? 0;
    return gradeNumberValidForTier(n, tier) ? t : null;
  }

  final leg = RegExp(r'^(초|중|고)(\d)$').firstMatch(t);
  if (leg != null) {
    final n = int.tryParse(leg.group(2)!) ?? 0;
    if (!gradeNumberValidForTier(n, tier)) return null;
    return '$n학년';
  }

  return null;
}

/// UI 한 줄용 (레거시 포함). 알 수 없으면 원문 반환.
String gradeDisplayLabel(String? stored) {
  if (stored == null) return '';
  final t = stored.trim();
  if (t.isEmpty) return '';
  if (RegExp(r'^\d+학년$').hasMatch(t)) return t;
  final leg = RegExp(r'^(초|중|고)(\d)$').firstMatch(t);
  if (leg != null) return '${leg.group(2)}학년';
  return t;
}

/// 검색 결과 외 UI용 짧은 학교명. [raw]는 `storageLabel`(지역 포함) 또는 코어명 모두 가능.
String shortSchoolDisplayName(String? raw) {
  if (raw == null) return '';
  final core = coreSchoolNameForTierHeuristic(raw.trim());
  if (core.isEmpty) return '';
  return shortenKoreanSchoolCoreName(core);
}

/// `숙명여자고등학교` → `숙명여고`, `상산고등학교` → `상산고`, `○○중학교` → `○○중`, `○○초등학교` → `○○초`
String shortenKoreanSchoolCoreName(String core) {
  var s = core.trim();
  if (s.isEmpty) return s;

  if (s.contains('여자고등학교')) {
    s = s.replaceAll('여자고등학교', '여고');
  } else if (s.contains('고등학교')) {
    s = s.replaceAll('고등학교', '고');
  }
  if (s.contains('중학교')) {
    s = s.replaceAll('중학교', '중');
  }
  if (s.contains('초등학교')) {
    s = s.replaceAll('초등학교', '초');
  }
  return s;
}

/// NEIS `SCHUL_KND_SC_NM` 값 기준(일반 초·중·고 및 유사 유형).
SchoolSearchTier? tierFromNeisSchoolKind(String? kind) {
  if (kind == null || kind.isEmpty) return null;
  final k = kind.trim();
  if (k.contains('초등')) return SchoolSearchTier.elementary;
  if (k.contains('중학')) return SchoolSearchTier.middle;
  if (k.contains('고등') || k.contains('고교')) {
    return SchoolSearchTier.high;
  }
  return null;
}

/// API/목록에 없을 때 학교명 문자열로 추정.
SchoolSearchTier heuristicTierFromName(String raw) {
  final n = raw.trim();
  if (n.contains('초등학교') || n.endsWith('초')) {
    return SchoolSearchTier.elementary;
  }
  if (n.contains('중학교') || n.endsWith('중')) {
    return SchoolSearchTier.middle;
  }
  if (n.contains('고등학교') ||
      n.contains('여고') ||
      n.contains('외고') ||
      n.contains('과고') ||
      n.contains('예고') ||
      n.endsWith('고')) {
    return SchoolSearchTier.high;
  }
  return SchoolSearchTier.middle;
}

/// 짧은 별칭(예: 이화여고) → 급. 전국 API 결과가 없을 때 보조.
const Map<String, SchoolSearchTier> koreanSchoolShortCatalog = {
  '이화여고': SchoolSearchTier.high,
  '개포고': SchoolSearchTier.high,
  '둔촌중': SchoolSearchTier.middle,
  '한영고': SchoolSearchTier.high,
  '배재고': SchoolSearchTier.high,
  '정신여고': SchoolSearchTier.high,
  '한빛초': SchoolSearchTier.elementary,
  '개포초': SchoolSearchTier.elementary,
};

String coreSchoolNameForTierHeuristic(String raw) {
  final t = raw.trim();
  final paren = t.lastIndexOf(' (');
  if (paren > 0 && t.endsWith(')')) {
    return t.substring(0, paren).trim();
  }
  return t;
}

SchoolSearchTier resolveTierForInput(
  String trimmedName, {
  SchoolSearchTier? lockedTier,
  String? lockedStorageKey,
  String? currentText,
}) {
  if (lockedTier != null &&
      lockedStorageKey != null &&
      currentText != null &&
      currentText.trim() == lockedStorageKey) {
    return lockedTier;
  }
  final core = coreSchoolNameForTierHeuristic(trimmedName);
  return koreanSchoolShortCatalog[core] ??
      koreanSchoolShortCatalog[trimmedName] ??
      heuristicTierFromName(core);
}

/// 검색 결과 한 행 (저장·표시용).
class KoreanSchoolHit {
  final String schoolName;
  final String region;
  final String schoolKind;
  final SchoolSearchTier tier;

  const KoreanSchoolHit({
    required this.schoolName,
    required this.region,
    required this.schoolKind,
    required this.tier,
  });

  /// 동일 이름 학교 구분: `가락고등학교 (서울특별시)`
  String get storageLabel => '$schoolName ($region)';

  String get subtitle => '$region · $schoolKind';
}
