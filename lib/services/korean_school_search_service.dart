import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/korean_school_search.dart';

/// 한국 전국 초·중·등 학교 검색.
///
/// 1) **나이스 교육정보 개방 포털** `schoolInfo` API (학교명 부분일치, 전국).
///    기본 키는 [_compileTimeDefaultNeisKey]이며, 배포 시에는
///    `--dart-define=NEIS_API_KEY=...` 로 덮어쓰는 것을 권장합니다.
/// 2) **오프라인 목록** `assets/data/korean_schools.json` (선택).
class KoreanSchoolSearchService {
  KoreanSchoolSearchService({
    http.Client? httpClient,
    String? neisApiKey,
  })  : _http = httpClient ?? http.Client(),
        _neisKey = neisApiKey ?? _keyFromEnvironment;

  final http.Client _http;
  final String _neisKey;

  static const String _envKeyName = 'NEIS_API_KEY';

  /// 로컬 개발용 기본값. 공개 저장소·스토어 빌드에는 `dart-define`만 쓰고
  /// 이 상수는 비워 두는 편이 안전합니다.
  static const String _compileTimeDefaultNeisKey =
      '2da097c8a5fd4444a2c695c1339261c4';

  static String get _keyFromEnvironment => const String.fromEnvironment(
        _envKeyName,
        defaultValue: _compileTimeDefaultNeisKey,
      );

  static bool get hasConfiguredNeisKey =>
      _keyFromEnvironment.trim().isNotEmpty;

  List<KoreanSchoolHit> _offlineHits = const [];
  bool _offlineLoaded = false;

  Future<void> ensureOfflineLoaded() async {
    if (_offlineLoaded) return;
    _offlineLoaded = true;
    try {
      final raw = await rootBundle.loadString('assets/data/korean_schools.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final out = <KoreanSchoolHit>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['n'] ?? item['name'] ?? '') as String? ?? '';
        final region = (item['r'] ?? item['region'] ?? '') as String? ?? '';
        final kind = (item['k'] ?? item['kind'] ?? '') as String? ?? '';
        if (name.isEmpty) continue;
        final tier = tierFromNeisSchoolKind(kind) ?? heuristicTierFromName(name);
        out.add(
          KoreanSchoolHit(
            schoolName: name.trim(),
            region: region.trim().isEmpty ? '지역 미상' : region.trim(),
            schoolKind: kind.trim().isEmpty ? '학교' : kind.trim(),
            tier: tier,
          ),
        );
      }
      _offlineHits = out;
    } catch (_) {
      _offlineHits = const [];
    }
  }

  List<KoreanSchoolHit> _filterOffline(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return _offlineHits
        .where((h) => h.schoolName.toLowerCase().contains(q))
        .take(80)
        .toList();
  }

  Future<List<KoreanSchoolHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    await ensureOfflineLoaded();
    final offline = _filterOffline(q);

    if (_neisKey.trim().isEmpty) {
      return offline;
    }

    try {
      final uri = Uri.https('open.neis.go.kr', '/hub/schoolInfo', {
        'KEY': _neisKey.trim(),
        'Type': 'json',
        'pIndex': '1',
        'pSize': '100',
        'SCHUL_NM': q,
      });
      final res = await _http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return offline;
      final apiHits = _parseNeisSchoolInfoJson(res.body);
      return _mergeHits(offline, apiHits);
    } catch (_) {
      return offline;
    }
  }

  List<KoreanSchoolHit> _mergeHits(
    List<KoreanSchoolHit> a,
    List<KoreanSchoolHit> b,
  ) {
    final seen = <String>{};
    final out = <KoreanSchoolHit>[];
    for (final h in [...b, ...a]) {
      final key = '${h.schoolName}|${h.region}';
      if (seen.add(key)) out.add(h);
      if (out.length >= 100) break;
    }
    return out;
  }

  List<KoreanSchoolHit> _parseNeisSchoolInfoJson(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded.containsKey('RESULT')) {
        final r = decoded['RESULT'];
        if (r is Map && r['CODE'] is String && r['CODE'] != 'INFO-000') {
          return const [];
        }
      }
      final schoolInfo = decoded['schoolInfo'];
      if (schoolInfo is! List) return const [];

      final out = <KoreanSchoolHit>[];
      for (final block in schoolInfo) {
        if (block is! Map<String, dynamic>) continue;
        final row = block['row'];
        if (row == null) continue;
        final rows = row is List ? row : [row];
        for (final item in rows) {
          if (item is! Map<String, dynamic>) continue;
          final name = '${item['SCHUL_NM'] ?? ''}'.trim();
          if (name.isEmpty) continue;
          final region = '${item['LCTN_SC_NM'] ?? ''}'.trim();
          final kind = '${item['SCHUL_KND_SC_NM'] ?? ''}'.trim();
          final tier =
              tierFromNeisSchoolKind(kind) ?? heuristicTierFromName(name);
          out.add(
            KoreanSchoolHit(
              schoolName: name,
              region: region.isEmpty ? '지역 미상' : region,
              schoolKind: kind.isEmpty ? '학교' : kind,
              tier: tier,
            ),
          );
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _http.close();
  }
}
