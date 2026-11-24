/*
 * LTv Juancho - fútbol: línea chica junto al reloj + panel con tus equipos.
 * Archivo nuevo; no forma parte del proyecto original.
 *
 * Datos: ESPN (gratis y SIN clave). Ya no se usa API-Football.
 *  - partidos pasados:   .../teams/{id}/schedule
 *  - partidos próximos:  .../teams/{id}/schedule?fixture=true
 *  - marcador en vivo:   .../{liga}/scoreboard
 *  - tabla de posiciones: .../{liga}/standings
 *
 * Para cambiar los equipos, editar la lista kFootballTeams
 * (liga = código de liga de ESPN, espnId = número del equipo en ESPN).
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/juancho_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Equipos
// ---------------------------------------------------------------------------

class FootballTeamDef {
  const FootballTeamDef({
    required this.key,
    required this.name,
    required this.short,
    required this.league,
    required this.espnId,
    required this.comps,
  });

  final String key; // id interno estable
  final String name; // nombre para mostrar
  final String short; // abreviatura de 3 letras
  final String league; // liga local en ESPN (col.1, eng.1, ita.1, ger.2...)
  final int espnId; // número del equipo en ESPN
  final List<String> comps; // todas las competiciones a revisar (liga + copas)
}

const List<FootballTeamDef> kFootballTeams = <FootballTeamDef>[
  FootballTeamDef(
    key: 'america',
    name: 'América de Cali',
    short: 'AME',
    league: 'col.1',
    espnId: 8109,
    comps: <String>['col.1', 'col.copa', 'conmebol.libertadores', 'conmebol.sudamericana'],
  ),
  FootballTeamDef(
    key: 'manutd',
    name: 'Manchester United',
    short: 'MUN',
    league: 'eng.1',
    espnId: 360,
    comps: <String>['eng.1', 'uefa.champions', 'uefa.europa', 'uefa.europa.conf', 'eng.fa', 'eng.league_cup'],
  ),
  FootballTeamDef(
    key: 'arsenal',
    name: 'Arsenal',
    short: 'ARS',
    league: 'eng.1',
    espnId: 359,
    comps: <String>['eng.1', 'uefa.champions', 'uefa.europa', 'uefa.europa.conf', 'eng.fa', 'eng.league_cup'],
  ),
  FootballTeamDef(
    key: 'milan',
    name: 'AC Milan',
    short: 'MIL',
    league: 'ita.1',
    espnId: 103,
    comps: <String>['ita.1', 'uefa.champions', 'uefa.europa', 'uefa.europa.conf', 'ita.coppa_italia'],
  ),
  FootballTeamDef(
    key: 'inter',
    name: 'Inter',
    short: 'INT',
    league: 'ita.1',
    espnId: 110,
    comps: <String>['ita.1', 'uefa.champions', 'uefa.europa', 'uefa.europa.conf', 'ita.coppa_italia'],
  ),
  FootballTeamDef(
    key: 'stpauli',
    name: 'St. Pauli',
    short: 'STP',
    league: 'ger.2',
    espnId: 270,
    comps: <String>['ger.2', 'ger.dfb_pokal'],
  ),
];

const Map<String, String> _leagueNames = <String, String>{
  'col.1': 'Liga BetPlay',
  'col.copa': 'Copa Colombia',
  'conmebol.libertadores': 'Libertadores',
  'conmebol.sudamericana': 'Sudamericana',
  'eng.1': 'Premier League',
  'eng.fa': 'FA Cup',
  'eng.league_cup': 'Carabao Cup',
  'ita.1': 'Serie A',
  'ita.coppa_italia': 'Coppa Italia',
  'ger.1': 'Bundesliga',
  'ger.2': '2. Bundesliga',
  'ger.dfb_pokal': 'DFB-Pokal',
  'uefa.champions': 'Champions League',
  'uefa.europa': 'Europa League',
  'uefa.europa.conf': 'Conference League',
};

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

const Set<String> _liveStatuses = <String>{'LIVE', 'HT'};
const Set<String> _finishedStatuses = <String>{'FT'};
const Set<String> _postponedStatuses = <String>{'PST', 'CANC', 'ABD'};

class FMatch {
  FMatch({
    required this.id,
    required this.kickoff,
    required this.status,
    required this.elapsed,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.goalsHome,
    required this.goalsAway,
    required this.league,
    required this.leagueName,
  });

  final int id;
  final DateTime kickoff;
  final String status; // NS, LIVE, HT, FT, PST, CANC, ABD
  final int? elapsed;
  final int homeId;
  final int awayId;
  final String homeName;
  final String awayName;
  final int? goalsHome;
  final int? goalsAway;
  final String league; // código ESPN de la liga (col.1, eng.1...)
  final String leagueName;

  bool get isLive => _liveStatuses.contains(status);
  bool get isFinished => _finishedStatuses.contains(status);
  bool get isPostponed => _postponedStatuses.contains(status);
  bool get isUpcoming => !isLive && !isFinished && !isPostponed;

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static int? _score(Object? v) {
    if (v is num) {
      return v.toInt();
    }
    if (v is String) {
      return int.tryParse(v);
    }
    if (v is Map) {
      return _score(v['value'] ?? v['displayValue']);
    }
    return null;
  }

  static int? _clockMinute(String clock) {
    final RegExpMatch? m = RegExp(r'(\d+)').firstMatch(clock);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Convierte un "evento" de ESPN en un partido. Devuelve null si no se entiende.
  static FMatch? fromEspn(Map<String, dynamic> ev, String league) {
    final List<dynamic> comps = (ev['competitions'] as List?) ?? const <dynamic>[];
    if (comps.isEmpty) {
      return null;
    }
    final Map<String, dynamic> comp = (comps.first as Map).cast<String, dynamic>();
    Map<String, dynamic>? home;
    Map<String, dynamic>? away;
    for (final dynamic c in (comp['competitors'] as List?) ?? const <dynamic>[]) {
      final Map<String, dynamic> m = (c as Map).cast<String, dynamic>();
      if (m['homeAway'] == 'home') {
        home = m;
      } else if (m['homeAway'] == 'away') {
        away = m;
      }
    }
    if (home == null || away == null) {
      return null;
    }
    final DateTime? kickoff = DateTime.tryParse('${ev['date'] ?? comp['date'] ?? ''}')?.toLocal();
    final int? id = int.tryParse('${ev['id'] ?? ''}');
    if (kickoff == null || id == null) {
      return null;
    }
    final Map<String, dynamic> ht = ((home['team'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
    final Map<String, dynamic> at = ((away['team'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
    final int? gh = _score(home['score']);
    final int? ga = _score(away['score']);

    String status = 'NS';
    int? elapsed;
    bool hadState = false;
    final Object? stRaw = comp['status'] ?? ev['status'];
    if (stRaw is Map) {
      final Map<String, dynamic> st = stRaw.cast<String, dynamic>();
      final Map<String, dynamic> type = ((st['type'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
      final String state = '${type['state'] ?? ''}';
      final String name = '${type['name'] ?? ''}'.toUpperCase();
      hadState = state.isNotEmpty;
      if (name.contains('POSTPONED')) {
        status = 'PST';
      } else if (name.contains('CANCEL')) {
        status = 'CANC';
      } else if (name.contains('SUSPEND') || name.contains('ABANDON')) {
        status = 'ABD';
      } else if (name.contains('HALFTIME')) {
        status = 'HT';
      } else if (state == 'in') {
        status = 'LIVE';
        elapsed = _clockMinute('${st['displayClock'] ?? ''}');
      } else if (state == 'post' || type['completed'] == true) {
        status = 'FT';
      }
    }
    // Si ESPN no dijo el estado pero ya hay marcador y pasaron casi 3 horas: terminó.
    if (!hadState &&
        status == 'NS' &&
        gh != null &&
        ga != null &&
        DateTime.now().difference(kickoff) > const Duration(minutes: 170)) {
      status = 'FT';
    }

    return FMatch(
      id: id,
      kickoff: kickoff,
      status: status,
      elapsed: elapsed,
      homeId: int.tryParse('${ht['id'] ?? ''}') ?? 0,
      awayId: int.tryParse('${at['id'] ?? ''}') ?? 0,
      homeName: '${ht['displayName'] ?? ht['name'] ?? ''}',
      awayName: '${at['displayName'] ?? at['name'] ?? ''}',
      goalsHome: gh,
      goalsAway: ga,
      league: league,
      leagueName: _leagueNames[league] ?? league,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'k': kickoff.millisecondsSinceEpoch,
        's': status,
        'e': elapsed,
        'hi': homeId,
        'ai': awayId,
        'hn': homeName,
        'an': awayName,
        'gh': goalsHome,
        'ga': goalsAway,
        'lg': league,
        'ln': leagueName,
      };

  factory FMatch.fromJson(Map<String, dynamic> j) => FMatch(
        id: _int(j['id']) ?? 0,
        kickoff: DateTime.fromMillisecondsSinceEpoch(_int(j['k']) ?? 0),
        status: '${j['s'] ?? 'NS'}',
        elapsed: _int(j['e']),
        homeId: _int(j['hi']) ?? 0,
        awayId: _int(j['ai']) ?? 0,
        homeName: '${j['hn'] ?? ''}',
        awayName: '${j['an'] ?? ''}',
        goalsHome: _int(j['gh']),
        goalsAway: _int(j['ga']),
        league: '${j['lg'] ?? ''}',
        leagueName: '${j['ln'] ?? ''}',
      );
}

class FRow {
  FRow({required this.rank, required this.teamId, required this.name, required this.points});

  final int rank;
  final int teamId;
  final String name;
  final int points;

  Map<String, dynamic> toJson() => <String, dynamic>{'r': rank, 'i': teamId, 'n': name, 'p': points};

  factory FRow.fromJson(Map<String, dynamic> j) => FRow(
        rank: (j['r'] as num?)?.toInt() ?? 0,
        teamId: (j['i'] as num?)?.toInt() ?? 0,
        name: '${j['n'] ?? ''}',
        points: (j['p'] as num?)?.toInt() ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Servicio
// ---------------------------------------------------------------------------

class FootballService extends ChangeNotifier {
  FootballService._();

  static final FootballService instance = FootballService._();

  static const String _prefsKey = 'juancho_football_cache_v2';
  static const String _base = 'https://site.api.espn.com/apis/site/v2/sports/soccer';
  static const String _baseV2 = 'https://site.api.espn.com/apis/v2/sports/soccer';

  bool _started = false;
  bool _busy = false;
  Timer? _timer;

  final Map<String, List<FMatch>> _matches = <String, List<FMatch>>{};
  final Map<String, int> _lastFetch = <String, int>{}; // ms por equipo
  final Map<String, int> _lastLive = <String, int>{}; // ms por liga
  final Map<String, List<FRow>> _standings = <String, List<FRow>>{};
  final Map<String, int> _standingsFetch = <String, int>{};

  // ultimo gol de uno de mis equipos (para el aviso "GOOOL")
  String? _goalKey;
  int _goalAt = 0;
  static const int _goalShowMs = 25000;

  /// Clave del equipo que acaba de meter gol (durante ~25 s), o null.
  String? get goalTeamKey {
    if (_goalKey != null && DateTime.now().millisecondsSinceEpoch - _goalAt < _goalShowMs) {
      return _goalKey;
    }
    return null;
  }

  // ESPN no pide clave: siempre activo.
  bool get enabled => true;

  List<FMatch> matchesOf(String key) => _matches[key] ?? const <FMatch>[];
  List<FRow> standingsOf(String key) => _standings[key] ?? const <FRow>[];

  int? teamIdOf(String key) {
    for (final FootballTeamDef t in kFootballTeams) {
      if (t.key == key) {
        return t.espnId;
      }
    }
    return null;
  }

  // ---- arranque ----

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _loadCache();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    unawaited(_tick());
  }

  // ---- cache ----

  Future<void> _loadCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null) {
        return;
      }
      final Map<String, dynamic> j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      ((j['matches'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        _matches['$k'] = <FMatch>[
          for (final Object? m in (v as List)) FMatch.fromJson((m as Map).cast<String, dynamic>()),
        ];
      });
      ((j['last'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        if (v is num) {
          _lastFetch['$k'] = v.toInt();
        }
      });
      ((j['stand'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        _standings['$k'] = <FRow>[
          for (final Object? r in (v as List)) FRow.fromJson((r as Map).cast<String, dynamic>()),
        ];
      });
      ((j['standTs'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        if (v is num) {
          _standingsFetch['$k'] = v.toInt();
        }
      });
    } catch (_) {
      // cache dañada: se ignora y se vuelve a pedir
    }
  }

  Future<void> _saveCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(<String, dynamic>{
          'matches': _matches.map((String k, List<FMatch> v) =>
              MapEntry<String, dynamic>(k, <Map<String, dynamic>>[for (final FMatch m in v) m.toJson()])),
          'last': _lastFetch,
          'stand': _standings.map((String k, List<FRow> v) =>
              MapEntry<String, dynamic>(k, <Map<String, dynamic>>[for (final FRow r in v) r.toJson()])),
          'standTs': _standingsFetch,
        }),
      );
    } catch (_) {}
  }

  // ---- red ----

  Future<Map<String, dynamic>?> _getJson(String url) async {
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Android TV) LTvJuancho');
      req.headers.set('Accept', 'application/json');
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 20));
      final String body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        return null;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  List<FMatch> _parseEvents(Map<String, dynamic>? j, String league) {
    final List<FMatch> out = <FMatch>[];
    if (j == null) {
      return out;
    }
    for (final dynamic ev in (j['events'] as List?) ?? const <dynamic>[]) {
      try {
        final FMatch? m = FMatch.fromEspn((ev as Map).cast<String, dynamic>(), league);
        if (m != null) {
          out.add(m);
        }
      } catch (_) {}
    }
    return out;
  }

  // Calendario completo del equipo en todas sus competiciones: lo jugado + lo que viene.
  Future<void> _fetchSchedule(FootballTeamDef t) async {
    final List<String> slugs = t.comps;
    final List<Map<String, dynamic>?> past = await Future.wait(<Future<Map<String, dynamic>?>>[
      for (final String c in slugs) _getJson('$_base/$c/teams/${t.espnId}/schedule'),
    ]);
    final List<Map<String, dynamic>?> next = await Future.wait(<Future<Map<String, dynamic>?>>[
      for (final String c in slugs) _getJson('$_base/$c/teams/${t.espnId}/schedule?fixture=true'),
    ]);
    _lastFetch[t.key] = DateTime.now().millisecondsSinceEpoch;
    if (past.every((Map<String, dynamic>? x) => x == null) && next.every((Map<String, dynamic>? x) => x == null)) {
      return;
    }
    final Map<int, FMatch> byId = <int, FMatch>{
      for (final FMatch m in _matches[t.key] ?? const <FMatch>[]) m.id: m,
    };
    // primero lo que viene, luego lo jugado (lo jugado manda si el partido sale en los dos)
    for (int i = 0; i < slugs.length; i++) {
      for (final FMatch m in _parseEvents(next[i], slugs[i])) {
        byId[m.id] = m;
      }
    }
    for (int i = 0; i < slugs.length; i++) {
      for (final FMatch m in _parseEvents(past[i], slugs[i])) {
        byId[m.id] = m;
      }
    }
    final DateTime now = DateTime.now();
    final List<FMatch> list = byId.values
        .where((FMatch m) =>
            m.kickoff.isAfter(now.subtract(const Duration(days: 45))) &&
            m.kickoff.isBefore(now.add(const Duration(days: 120))))
        .toList()
      ..sort((FMatch a, FMatch b) => a.kickoff.compareTo(b.kickoff));
    _matches[t.key] = list;
  }

  // Marcador en vivo de una competicion: una sola peticion sirve para todos mis equipos que jueguen ahi.
  Future<void> _fetchLive(String league) async {
    final int prevLive = _lastLive[league] ?? 0;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastLive[league] = nowMs;
    final Map<String, dynamic>? j = await _getJson('$_base/$league/scoreboard');
    for (final FMatch m in _parseEvents(j, league)) {
      for (final FootballTeamDef t in kFootballTeams) {
        if (m.homeId != t.espnId && m.awayId != t.espnId) {
          continue;
        }
        final List<FMatch> list = _matches.putIfAbsent(t.key, () => <FMatch>[]);
        final int idx = list.indexWhere((FMatch x) => x.id == m.id);
        if (idx >= 0) {
          final FMatch old = list[idx];
          // ¿gol de mi equipo? (solo si ya veniamos siguiendo el partido)
          final bool following = old.isLive || (old.status == 'NS' && nowMs - prevLive < 10 * 60000);
          if (following && m.isLive) {
            final bool home = m.homeId == t.espnId;
            final int before = (home ? old.goalsHome : old.goalsAway) ?? 0;
            final int after = (home ? m.goalsHome : m.goalsAway) ?? 0;
            if (after > before) {
              _goalKey = t.key;
              _goalAt = nowMs;
              Timer(const Duration(milliseconds: _goalShowMs + 1000), notifyListeners);
            }
          }
          list[idx] = m;
        } else {
          list.add(m);
          list.sort((FMatch a, FMatch b) => a.kickoff.compareTo(b.kickoff));
        }
      }
    }
    notifyListeners();
  }

  static num? _stat(Object? stats, String name) {
    if (stats is! List) {
      return null;
    }
    for (final dynamic s in stats) {
      if (s is Map && s['name'] == name && s['value'] is num) {
        return s['value'] as num;
      }
    }
    return null;
  }

  Future<void> _fetchStandings(FootballTeamDef t) async {
    final Map<String, dynamic>? j = await _getJson('$_baseV2/${t.league}/standings');
    _standingsFetch[t.key] = DateTime.now().millisecondsSinceEpoch;
    if (j == null) {
      return;
    }
    try {
      // varios grupos (torneos con fases, como la liga colombiana): se toma el que contiene al equipo
      final List<dynamic> groups = <dynamic>[
        ...((j['children'] as List?) ?? const <dynamic>[]),
        if (j['standings'] is Map) j,
      ];
      for (final dynamic g in groups) {
        final List<dynamic> entries =
            (((g as Map)['standings'] as Map?)?['entries'] as List?) ?? const <dynamic>[];
        final List<FRow> rows = <FRow>[];
        for (int i = 0; i < entries.length; i++) {
          final Map<String, dynamic> e = (entries[i] as Map).cast<String, dynamic>();
          final Map<String, dynamic> team = ((e['team'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
          rows.add(FRow(
            rank: _stat(e['stats'], 'rank')?.toInt() ?? (i + 1),
            teamId: int.tryParse('${team['id'] ?? ''}') ?? 0,
            name: '${team['displayName'] ?? team['name'] ?? ''}',
            points: _stat(e['stats'], 'points')?.toInt() ?? 0,
          ));
        }
        if (rows.any((FRow r) => r.teamId == t.espnId)) {
          rows.sort((FRow a, FRow b) => a.rank.compareTo(b.rank));
          _standings[t.key] = rows;
          return;
        }
      }
    } catch (_) {}
  }

  // ---- ciclo ----

  Future<void> _tick() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final int now = DateTime.now().millisecondsSinceEpoch;
      // competicion -> true si hay un partido de mis equipos jugandose ya
      final Map<String, bool> windows = <String, bool>{};

      for (final FootballTeamDef t in kFootballTeams) {
        for (final FMatch m in _matches[t.key] ?? const <FMatch>[]) {
          final int k = m.kickoff.millisecondsSinceEpoch;
          // en juego o por empezar
          if (!m.isFinished && !m.isPostponed && now > k - 10 * 60000 && now < k + 150 * 60000) {
            windows[m.league] = (windows[m.league] ?? false) || m.isLive;
          }
        }
      }
      // lo en vivo va primero para que un calendario lento no lo retrase
      for (final MapEntry<String, bool> w in windows.entries) {
        final int gap = w.value ? 25000 : const Duration(minutes: 2).inMilliseconds;
        if (now - (_lastLive[w.key] ?? 0) > gap) {
          await _fetchLive(w.key);
        }
      }

      for (final FootballTeamDef t in kFootballTeams) {
        final int last = _lastFetch[t.key] ?? 0;
        final List<FMatch> list = _matches[t.key] ?? const <FMatch>[];

        bool stale = list.isEmpty ? now - last > 3 * 60000 : now - last > const Duration(hours: 6).inMilliseconds;
        for (final FMatch m in list) {
          final int k = m.kickoff.millisecondsSinceEpoch;
          // ya debio terminar y aun figura sin resultado final: pedir de nuevo
          if (!m.isFinished &&
              !m.isPostponed &&
              now > k + 110 * 60000 &&
              now < k + 8 * 3600000 &&
              now - last > 10 * 60000) {
            stale = true;
          }
        }
        if (stale) {
          await _fetchSchedule(t);
        }
        final int lastStand = _standingsFetch[t.key] ?? 0;
        final bool standStale = _standings[t.key] == null
            ? now - lastStand > 10 * 60000
            : now - lastStand > const Duration(hours: 6).inMilliseconds;
        if (standStale) {
          await _fetchStandings(t);
        }
      }
    } finally {
      _busy = false;
      await _saveCache();
      notifyListeners();
    }
  }

  // ---- reglas de presentacion ----

  /// Filas a mostrar: del 1 al 5 si el equipo esta en el top 5;
  /// si no, el de arriba, el equipo y el de abajo.
  List<FRow> windowFor(String key) {
    final List<FRow> rows = standingsOf(key);
    final int? id = teamIdOf(key);
    if (rows.isEmpty || id == null) {
      return const <FRow>[];
    }
    final int idx = rows.indexWhere((FRow r) => r.teamId == id);
    if (idx < 0) {
      return const <FRow>[];
    }
    if (rows[idx].rank <= 5) {
      return rows.take(5).toList();
    }
    final int from = (idx - 1).clamp(0, rows.length - 1).toInt();
    final int to = (idx + 1).clamp(0, rows.length - 1).toInt();
    return rows.sublist(from, to + 1);
  }

  /// Partido que vale la pena mostrar ahora para un equipo (o null).
  FMatch? featuredFor(String key) {
    final List<FMatch> list = matchesOf(key);
    if (list.isEmpty) {
      return null;
    }
    final DateTime now = DateTime.now();
    FMatch? live;
    FMatch? recentFinal;
    FMatch? soon;
    for (final FMatch m in list) {
      if (m.isLive) {
        live = m;
      } else if (m.isFinished && now.difference(m.kickoff) < const Duration(hours: 22) && !m.kickoff.isAfter(now)) {
        recentFinal = m; // el mas reciente (la lista va ordenada)
      } else if (m.isUpcoming && m.kickoff.isAfter(now.subtract(const Duration(minutes: 15)))) {
        if (soon == null && m.kickoff.difference(now) < const Duration(hours: 72)) {
          soon = m;
        }
      }
    }
    return live ?? soon ?? recentFinal;
  }

  FMatch? lastPlayed(String key) {
    FMatch? r;
    for (final FMatch m in matchesOf(key)) {
      if (m.isFinished) {
        r = m;
      }
    }
    return r;
  }

  FMatch? nextMatch(String key) {
    final DateTime now = DateTime.now();
    for (final FMatch m in matchesOf(key)) {
      if (m.isUpcoming && m.kickoff.isAfter(now.subtract(const Duration(minutes: 15)))) {
        return m;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

String _hora(DateTime t) {
  final int h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String min = t.minute.toString().padLeft(2, '0');
  return '$h12:$min ${t.hour < 12 ? 'a. m.' : 'p. m.'}';
}

String _dia(DateTime t) {
  final DateTime now = DateTime.now();
  final DateTime a = DateTime(now.year, now.month, now.day);
  final DateTime b = DateTime(t.year, t.month, t.day);
  final int diff = b.difference(a).inDays;
  if (diff == 0) {
    return 'Hoy';
  }
  if (diff == 1) {
    return 'Mañana';
  }
  if (diff == -1) {
    return 'Ayer';
  }
  const List<String> dias = <String>['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  const List<String> meses = <String>['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${dias[t.weekday - 1]} ${t.day} ${meses[t.month - 1]}';
}

String _corto(String name) {
  String n = name.trim();
  const Map<String, String> map = <String, String>{
    'Manchester United': 'Man United',
    'Manchester City': 'Man City',
    'Tottenham Hotspur': 'Spurs',
    'Newcastle United': 'Newcastle',
    'Nottingham Forest': 'Forest',
    'Wolverhampton Wanderers': 'Wolves',
    'West Ham United': 'West Ham',
    'Leeds United': 'Leeds',
    'Crystal Palace': 'Palace',
    'Brighton & Hove Albion': 'Brighton',
    'AFC Bournemouth': 'Bournemouth',
    'Aston Villa': 'Aston Villa',
    'AC Milan': 'Milan',
    'Internazionale': 'Inter',
    'América de Cali': 'América',
    'Atlético Nacional': 'Nacional',
    'Atlético Bucaramanga': 'Bucaramanga',
    'Atlético Junior': 'Junior',
    'Independiente Medellín': 'Medellín',
    'Independiente Santa Fe': 'Santa Fe',
    'Deportivo Cali': 'Dep. Cali',
    'Deportivo Pereira': 'Pereira',
    'Deportivo Pasto': 'Pasto',
    'Deportes Tolima': 'Tolima',
    'Águilas Doradas': 'Águilas',
    'Jaguares de Córdoba': 'Jaguares',
    'Internacional de Bogotá': 'Int. Bogotá',
    'Cúcuta Deportivo': 'Cúcuta',
    'Boyacá Chicó FC': 'Boyacá Chicó',
    'Fortaleza CEIF': 'Fortaleza',
    'Llaneros FC': 'Llaneros',
    'Alianza FC': 'Alianza',
    'Borussia Dortmund': 'Dortmund',
    'Bayern Munich': 'Bayern',
    'Bayer Leverkusen': 'Leverkusen',
  };
  n = map[n] ?? n;
  return n.length > 12 ? n.substring(0, 12) : n;
}

String matchText(FMatch m, FootballTeamDef t) {
  final String hs = _shortTeam(m.homeName, m.homeId, t);
  final String vs = _shortTeam(m.awayName, m.awayId, t);
  final String score = '${m.goalsHome ?? 0}–${m.goalsAway ?? 0}';
  if (m.isLive) {
    final String minute = m.status == 'HT' ? 'ENT' : (m.elapsed != null ? "${m.elapsed}'" : 'VIVO');
    return '$minute  $hs $score $vs';
  }
  if (m.isFinished) {
    return '${_dia(m.kickoff)} · $hs $score $vs · final';
  }
  return '${_dia(m.kickoff)} ${_hora(m.kickoff)} · $hs vs $vs';
}

String _shortTeam(String apiName, int id, FootballTeamDef mine) {
  if (id == mine.espnId) {
    return mine.short;
  }
  return _corto(apiName);
}

// ---------------------------------------------------------------------------
// Línea chica junto al reloj
// ---------------------------------------------------------------------------

class FootballLine extends StatefulWidget {
  const FootballLine({super.key, this.compact = false});

  final bool compact;

  @override
  State<FootballLine> createState() => _FootballLineState();
}

class _FootballLineState extends State<FootballLine> {
  final FocusNode _node = FocusNode(debugLabel: 'football-line');
  Timer? _rot;
  int _turn = 0;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FootballService.instance.addListener(_onData);
    FootballService.instance.start();
    _rot = Timer.periodic(const Duration(seconds: 9), (_) {
      if (mounted && !_focused) {
        setState(() => _turn++);
      }
    });
  }

  @override
  void dispose() {
    FootballService.instance.removeListener(_onData);
    _rot?.cancel();
    _node.dispose();
    super.dispose();
  }

  void _onData() {
    if (mounted) {
      setState(() {});
    }
  }

  // equipos con algo que contar ahora, los en vivo primero
  List<(FootballTeamDef, FMatch)> _candidates() {
    final FootballService s = FootballService.instance;
    final List<(FootballTeamDef, FMatch)> live = <(FootballTeamDef, FMatch)>[];
    final List<(FootballTeamDef, FMatch)> rest = <(FootballTeamDef, FMatch)>[];
    for (final FootballTeamDef t in kFootballTeams) {
      // siempre algo que mostrar: lo de ahora, si no el proximo partido, si no el ultimo
      final FMatch? m = s.featuredFor(t.key) ?? s.nextMatch(t.key) ?? s.lastPlayed(t.key);
      if (m == null) {
        continue;
      }
      (m.isLive ? live : rest).add((t, m));
    }
    return <(FootballTeamDef, FMatch)>[...live, ...rest];
  }

  Widget _chips(FootballTeamDef t, FMatch m) {
    final FootballService s = FootballService.instance;
    final bool domestic = s.standingsOf(t.key).isNotEmpty && m.league == t.league;
    if (!domestic) {
      return Text(
        m.leagueName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
      );
    }
    final int? myId = s.teamIdOf(t.key);
    final List<FRow> rows = s.windowFor(t.key);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 10),
          Text(
            '${rows[i].rank}º ${_corto(rows[i].name)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: rows[i].teamId == myId ? FontWeight.w800 : FontWeight.w400,
              color: rows[i].teamId == myId ? Colors.white : Colors.white.withOpacity(0.62),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final FootballService s = FootballService.instance;
    if (!s.enabled) {
      return const SizedBox.shrink();
    }
    final List<(FootballTeamDef, FMatch)> cands = _candidates();
    if (cands.isEmpty) {
      return const SizedBox.shrink();
    }
    // si uno de mis equipos acaba de meter gol, ese pasa al frente
    final String? goalKey = s.goalTeamKey;
    int pick = _turn % cands.length;
    if (goalKey != null) {
      final int gi = cands.indexWhere(((FootballTeamDef, FMatch) c) => c.$1.key == goalKey);
      if (gi >= 0) {
        pick = gi;
      }
    }
    final (FootballTeamDef t, FMatch m) = cands[pick];
    final bool goal = goalKey != null && t.key == goalKey;

    return FocusKeyboardListener(
      onPressed: (LogicalKeyboardKey key) {
        if (AppCardKeys.validationKeys.contains(key)) {
          showFootballPanel(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onLongPress: (LogicalKeyboardKey key) {
        showFootballPanel(context);
        return KeyEventResult.handled;
      },
      builder: (BuildContext context) => Focus(
        focusNode: _node,
        onFocusChange: (bool f) {
          if (mounted) {
            setState(() => _focused = f);
          }
        },
        child: GestureDetector(
          onTap: () => showFootballPanel(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(_focused ? 0.45 : 0.28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: goal
                    ? kJuanchoEmber
                    : (_focused ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.12)),
                width: (_focused || goal) ? 2 : 1,
              ),
              boxShadow: goal
                  ? <BoxShadow>[BoxShadow(color: kJuanchoGlow.withOpacity(0.85), blurRadius: 30, spreadRadius: 2)]
                  : (_focused ? <BoxShadow>[BoxShadow(color: kJuanchoGlow.withOpacity(0.5), blurRadius: 20)] : null),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: Column(
                key: ValueKey<String>('${t.key}_${m.id}_${m.status}_${m.goalsHome}_${m.goalsAway}_$goal'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (m.isLive) ...<Widget>[
                        const _LiveDot(),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          matchText(m, t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1))],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (goal)
                    const Text(
                      '⚽ ¡GOOOL!',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kJuanchoEmber),
                    )
                  else
                    _chips(t, m),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panel con todos los equipos
// ---------------------------------------------------------------------------

Future<void> showFootballPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (BuildContext ctx) => const _FootballPanel(),
  );
}

class _FootballPanel extends StatelessWidget {
  const _FootballPanel();

  @override
  Widget build(BuildContext context) {
    final FootballService s = FootballService.instance;
    return Dialog(
      backgroundColor: const Color(0xF0141418),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Mis equipos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              for (final FootballTeamDef t in kFootballTeams) _teamRow(context, s, t),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamRow(BuildContext context, FootballService s, FootballTeamDef t) {
    final FMatch? last = s.lastPlayed(t.key);
    final FMatch? next = s.nextMatch(t.key);
    final List<FRow> rows = s.standingsOf(t.key);
    final int? id = s.teamIdOf(t.key);
    FRow? mine;
    for (final FRow r in rows) {
      if (r.teamId == id) {
        mine = r;
      }
    }
    final TextStyle dim = TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.72));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 4,
            height: 46,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(color: kJuanchoGlow, borderRadius: BorderRadius.circular(2)),
          ),
          SizedBox(
            width: 190,
            child: Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(last == null ? 'Último: sin datos' : 'Último: ${matchText(last, t)}', style: dim),
                const SizedBox(height: 3),
                Text(next == null ? 'Próximo: sin fecha' : 'Próximo: ${matchText(next, t)}', style: dim),
                if (mine != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text('Liga: ${mine.rank}º · ${mine.points} pts', style: dim),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
