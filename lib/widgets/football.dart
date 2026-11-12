/*
 * LTv Juancho - fútbol: línea chica junto al reloj + panel con tus equipos.
 * Archivo nuevo; no forma parte del proyecto original.
 *
 * Datos: API-Football (plan gratis, 100 peticiones al día). La clave NO va en el
 * código: se deja en un archivo dentro de la carpeta de la app en la TV
 * (ver script 17-clave-futbol.ps1). Sin clave, todo esto queda oculto.
 *
 * Para cambiar los equipos, editar la lista kFootballTeams.
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
    required this.search,
    required this.country,
    required this.calendarSeason,
  });

  final String key; // id interno estable
  final String name; // nombre para mostrar
  final String short; // abreviatura de 3 letras
  final String search; // texto para buscar en la API
  final String country; // filtro de pais para la busqueda
  final bool calendarSeason; // true: temporada = año (Colombia); false: europea
}

const List<FootballTeamDef> kFootballTeams = <FootballTeamDef>[
  FootballTeamDef(
      key: 'america', name: 'América de Cali', short: 'AME', search: 'America de Cali', country: 'Colombia', calendarSeason: true),
  FootballTeamDef(
      key: 'milan', name: 'AC Milan', short: 'MIL', search: 'AC Milan', country: 'Italy', calendarSeason: false),
  FootballTeamDef(
      key: 'inter', name: 'Inter', short: 'INT', search: 'Inter', country: 'Italy', calendarSeason: false),
  FootballTeamDef(
      key: 'manutd',
      name: 'Manchester United',
      short: 'MUN',
      search: 'Manchester United',
      country: 'England',
      calendarSeason: false),
  FootballTeamDef(
      key: 'arsenal', name: 'Arsenal', short: 'ARS', search: 'Arsenal', country: 'England', calendarSeason: false),
];

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

const Set<String> _liveStatuses = <String>{'1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE', 'INT'};
const Set<String> _finishedStatuses = <String>{'FT', 'AET', 'PEN'};

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
    required this.leagueId,
    required this.leagueName,
    required this.round,
  });

  final int id;
  final DateTime kickoff;
  final String status;
  final int? elapsed;
  final int homeId;
  final int awayId;
  final String homeName;
  final String awayName;
  final int? goalsHome;
  final int? goalsAway;
  final int leagueId;
  final String leagueName;
  final String round;

  bool get isLive => _liveStatuses.contains(status);
  bool get isFinished => _finishedStatuses.contains(status);
  bool get isPostponed => status == 'PST' || status == 'CANC' || status == 'ABD' || status == 'AWD' || status == 'WO';
  bool get isUpcoming => !isLive && !isFinished && !isPostponed;

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  factory FMatch.fromApi(Map<String, dynamic> j) {
    final Map<String, dynamic> fx = (j['fixture'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> teams = (j['teams'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> home = (teams['home'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> away = (teams['away'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> goals = ((j['goals'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
    final Map<String, dynamic> league = (j['league'] as Map).cast<String, dynamic>();
    final Map<String, dynamic> st = ((fx['status'] ?? <String, dynamic>{}) as Map).cast<String, dynamic>();
    return FMatch(
      id: _int(fx['id']) ?? 0,
      kickoff: DateTime.tryParse('${fx['date']}')?.toLocal() ?? DateTime.now(),
      status: '${st['short'] ?? 'NS'}',
      elapsed: _int(st['elapsed']),
      homeId: _int(home['id']) ?? 0,
      awayId: _int(away['id']) ?? 0,
      homeName: '${home['name'] ?? ''}',
      awayName: '${away['name'] ?? ''}',
      goalsHome: _int(goals['home']),
      goalsAway: _int(goals['away']),
      leagueId: _int(league['id']) ?? 0,
      leagueName: '${league['name'] ?? ''}',
      round: '${league['round'] ?? ''}',
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
        'li': leagueId,
        'ln': leagueName,
        'r': round,
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
        leagueId: _int(j['li']) ?? 0,
        leagueName: '${j['ln'] ?? ''}',
        round: '${j['r'] ?? ''}',
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

  static const String _prefsKey = 'juancho_football_cache_v1';
  static const int _dailyLimit = 94; // el plan gratis da 100: dejo margen

  String? _apiKey;
  bool _started = false;
  bool _busy = false;
  Timer? _timer;
  String _packageName = 'com.leanbitlab.ltvL.juancho';

  final Map<String, int> _teamIds = <String, int>{};
  final Map<String, List<FMatch>> _matches = <String, List<FMatch>>{};
  final Map<String, int> _lastFetch = <String, int>{}; // ms por equipo
  final Map<String, int> _domesticLeague = <String, int>{};
  final Map<String, List<FRow>> _standings = <String, List<FRow>>{};
  final Map<String, int> _standingsFetch = <String, int>{};
  String _dayKey = '';
  int _dayCount = 0;
  int _lastLiveCall = 0;

  bool get enabled => _apiKey != null;

  List<FMatch> matchesOf(String key) => _matches[key] ?? const <FMatch>[];
  List<FRow> standingsOf(String key) => _standings[key] ?? const <FRow>[];
  int? teamIdOf(String key) => _teamIds[key];

  // ---- arranque ----

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      final String cmd = await File('/proc/self/cmdline').readAsString();
      final String pkg = cmd.split('\u0000').first.trim();
      if (pkg.isNotEmpty && pkg.contains('.')) {
        _packageName = pkg;
      }
    } catch (_) {}
    // crea la carpeta donde se deja la clave
    try {
      await Directory(_keyDir()).create(recursive: true);
    } catch (_) {}
    await _loadCache();
    await _loadKey();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _tick());
    unawaited(_tick());
  }

  String _keyDir() => '/storage/emulated/0/Android/data/$_packageName/files';

  Future<void> _loadKey() async {
    try {
      final File f = File('${_keyDir()}/futbol-clave.txt');
      if (await f.exists()) {
        final String k = (await f.readAsString()).trim();
        _apiKey = k.length >= 8 ? k : null;
      } else {
        _apiKey = null;
      }
    } catch (_) {
      _apiKey = null;
    }
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
      ((j['ids'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        if (v is num) {
          _teamIds['$k'] = v.toInt();
        }
      });
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
      ((j['dom'] ?? <String, dynamic>{}) as Map).forEach((Object? k, Object? v) {
        if (v is num) {
          _domesticLeague['$k'] = v.toInt();
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
      _dayKey = '${j['day'] ?? ''}';
      _dayCount = (j['count'] as num?)?.toInt() ?? 0;
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
          'ids': _teamIds,
          'matches': _matches.map((String k, List<FMatch> v) =>
              MapEntry<String, dynamic>(k, <Map<String, dynamic>>[for (final FMatch m in v) m.toJson()])),
          'last': _lastFetch,
          'dom': _domesticLeague,
          'stand': _standings.map((String k, List<FRow> v) =>
              MapEntry<String, dynamic>(k, <Map<String, dynamic>>[for (final FRow r in v) r.toJson()])),
          'standTs': _standingsFetch,
          'day': _dayKey,
          'count': _dayCount,
        }),
      );
    } catch (_) {}
  }

  // ---- red ----

  String _today() {
    final DateTime n = DateTime.now().toUtc(); // la cuota se reinicia a las 00:00 UTC
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) async {
    final String key = _apiKey ?? '';
    if (key.isEmpty) {
      return null;
    }
    final String today = _today();
    if (_dayKey != today) {
      _dayKey = today;
      _dayCount = 0;
    }
    if (_dayCount >= _dailyLimit) {
      return null;
    }
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final HttpClientRequest req = await client.getUrl(Uri.https('v3.football.api-sports.io', path, query));
      req.headers.set('x-apisports-key', key);
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 20));
      final String body = await res.transform(utf8.decoder).join();
      _dayCount++;
      if (res.statusCode != 200) {
        return null;
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }
      final Map<String, dynamic> j = decoded.cast<String, dynamic>();
      final Object? errs = j['errors'];
      if ((errs is Map && errs.isNotEmpty) || (errs is List && errs.isNotEmpty)) {
        return null;
      }
      return j;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  int _seasonFor(FootballTeamDef t) {
    final DateTime n = DateTime.now();
    if (t.calendarSeason) {
      return n.year;
    }
    return n.month >= 7 ? n.year : n.year - 1;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _resolveTeamId(FootballTeamDef t) async {
    final Map<String, dynamic>? j = await _get('/teams', <String, String>{'search': t.search, 'country': t.country});
    if (j == null) {
      return;
    }
    final List<dynamic> list = (j['response'] as List?) ?? const <dynamic>[];
    int? exact;
    int? partial;
    for (final dynamic item in list) {
      final Map<String, dynamic>? team = ((item as Map)['team'] as Map?)?.cast<String, dynamic>();
      if (team == null) {
        continue;
      }
      final String n = _norm('${team['name']}');
      final int? id = (team['id'] as num?)?.toInt();
      if (id == null) {
        continue;
      }
      if (n == _norm(t.search)) {
        exact = id;
        break;
      }
      if (partial == null && n.contains(_norm(t.search))) {
        partial = id;
      }
    }
    final int? chosen = exact ?? partial;
    if (chosen != null) {
      _teamIds[t.key] = chosen;
    }
  }

  Future<void> _fetchSeason(FootballTeamDef t) async {
    final int? id = _teamIds[t.key];
    if (id == null) {
      return;
    }
    final Map<String, dynamic>? j =
        await _get('/fixtures', <String, String>{'team': '$id', 'season': '${_seasonFor(t)}'});
    _lastFetch[t.key] = DateTime.now().millisecondsSinceEpoch;
    if (j == null) {
      return;
    }
    final List<FMatch> list = <FMatch>[];
    for (final dynamic item in (j['response'] as List?) ?? const <dynamic>[]) {
      try {
        list.add(FMatch.fromApi((item as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    list.sort((FMatch a, FMatch b) => a.kickoff.compareTo(b.kickoff));
    _matches[t.key] = list;

    // la liga local es la competicion donde mas juega el equipo
    final Map<int, int> counts = <int, int>{};
    for (final FMatch m in list) {
      counts[m.leagueId] = (counts[m.leagueId] ?? 0) + 1;
    }
    int best = -1;
    int bestCount = 0;
    counts.forEach((int lid, int c) {
      if (c > bestCount) {
        best = lid;
        bestCount = c;
      }
    });
    if (best > 0) {
      _domesticLeague[t.key] = best;
    }
  }

  Future<void> _fetchStandings(FootballTeamDef t) async {
    final int? league = _domesticLeague[t.key];
    final int? teamId = _teamIds[t.key];
    if (league == null || teamId == null) {
      return;
    }
    final Map<String, dynamic>? j =
        await _get('/standings', <String, String>{'league': '$league', 'season': '${_seasonFor(t)}'});
    _standingsFetch[t.key] = DateTime.now().millisecondsSinceEpoch;
    if (j == null) {
      return;
    }
    try {
      final List<dynamic> resp = (j['response'] as List?) ?? const <dynamic>[];
      if (resp.isEmpty) {
        return;
      }
      final List<dynamic> groups = ((resp.first as Map)['league'] as Map)['standings'] as List;
      // varios grupos (torneos con fases): se toma el que contiene al equipo
      List<dynamic>? chosen;
      for (final dynamic g in groups) {
        final List<dynamic> rows = g as List;
        if (rows.any((dynamic r) => ((r as Map)['team'] as Map)['id'] == teamId)) {
          chosen = rows;
          break;
        }
      }
      if (chosen == null) {
        return;
      }
      _standings[t.key] = <FRow>[
        for (final dynamic r in chosen)
          FRow(
            rank: ((r as Map)['rank'] as num?)?.toInt() ?? 0,
            teamId: (((r['team']) as Map)['id'] as num?)?.toInt() ?? 0,
            name: '${(r['team'] as Map)['name']}',
            points: (r['points'] as num?)?.toInt() ?? 0,
          ),
      ]..sort((FRow a, FRow b) => a.rank.compareTo(b.rank));
    } catch (_) {}
  }

  // Partidos en vivo de mis equipos: una sola peticion para todos.
  Future<void> _pollLive() async {
    _lastLiveCall = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic>? j = await _get('/fixtures', <String, String>{'live': 'all'});
    if (j == null) {
      return;
    }
    for (final dynamic item in (j['response'] as List?) ?? const <dynamic>[]) {
      try {
        final FMatch m = FMatch.fromApi((item as Map).cast<String, dynamic>());
        for (final FootballTeamDef t in kFootballTeams) {
          final int? id = _teamIds[t.key];
          if (id == null || (m.homeId != id && m.awayId != id)) {
            continue;
          }
          final List<FMatch> list = _matches.putIfAbsent(t.key, () => <FMatch>[]);
          final int idx = list.indexWhere((FMatch x) => x.id == m.id);
          if (idx >= 0) {
            list[idx] = m;
          } else {
            list.add(m);
            list.sort((FMatch a, FMatch b) => a.kickoff.compareTo(b.kickoff));
          }
        }
      } catch (_) {}
    }
  }

  // ---- ciclo ----

  Future<void> _tick() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      if (_apiKey == null) {
        await _loadKey();
        if (_apiKey == null) {
          return;
        }
      }
      final int now = DateTime.now().millisecondsSinceEpoch;

      for (final FootballTeamDef t in kFootballTeams) {
        if (!_teamIds.containsKey(t.key)) {
          await _resolveTeamId(t);
        }
      }

      bool anyInWindow = false;
      for (final FootballTeamDef t in kFootballTeams) {
        if (!_teamIds.containsKey(t.key)) {
          continue;
        }
        final int last = _lastFetch[t.key] ?? 0;
        final List<FMatch> list = _matches[t.key] ?? const <FMatch>[];

        bool stale = now - last > const Duration(hours: 6).inMilliseconds;
        for (final FMatch m in list) {
          final int k = m.kickoff.millisecondsSinceEpoch;
          // en juego o por empezar
          if (!m.isFinished && !m.isPostponed && now > k - 10 * 60000 && now < k + 150 * 60000) {
            anyInWindow = true;
          }
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
          await _fetchSeason(t);
        }
        if (_standings[t.key] == null || now - (_standingsFetch[t.key] ?? 0) > const Duration(hours: 12).inMilliseconds) {
          if (_domesticLeague.containsKey(t.key)) {
            await _fetchStandings(t);
          }
        }
      }

      if (anyInWindow && now - _lastLiveCall > const Duration(minutes: 3).inMilliseconds) {
        await _pollLive();
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
    final int? id = _teamIds[key];
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

String _ronda(String r) {
  final String l = r.toLowerCase();
  if (l.contains('round of 16')) return 'Octavos';
  if (l.contains('quarter')) return 'Cuartos';
  if (l.contains('semi')) return 'Semifinal';
  if (l.contains('play-off') || l.contains('playoff')) return 'Playoff';
  if (l == 'final') return 'Final';
  if (l.contains('league stage')) return 'Fase de liga';
  if (l.contains('group')) return 'Fase de grupos';
  return r;
}

String _corto(String name) {
  String n = name.trim();
  const Map<String, String> map = <String, String>{
    'Manchester United': 'Man United',
    'Manchester City': 'Man City',
    'Tottenham': 'Spurs',
    'Newcastle': 'Newcastle',
    'Nottingham Forest': 'Forest',
    'Wolves': 'Wolves',
    'AC Milan': 'Milan',
    'America de Cali': 'América',
  };
  n = map[n] ?? n;
  return n.length > 11 ? n.substring(0, 11) : n;
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
  final int? myId = FootballService.instance.teamIdOf(mine.key);
  if (myId != null && id == myId) {
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
      final FMatch? m = s.featuredFor(t.key);
      if (m == null) {
        continue;
      }
      (m.isLive ? live : rest).add((t, m));
    }
    return <(FootballTeamDef, FMatch)>[...live, ...rest];
  }

  Widget _chips(FootballTeamDef t, FMatch m) {
    final FootballService s = FootballService.instance;
    final bool domestic = s.standingsOf(t.key).isNotEmpty && m.leagueId == _domesticOf(t);
    if (!domestic) {
      return Text(
        '${m.leagueName} · ${_ronda(m.round)}',
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

  int? _domesticOf(FootballTeamDef t) => FootballService.instance._domesticLeague[t.key];

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
    final (FootballTeamDef t, FMatch m) = cands[_turn % cands.length];

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
                color: _focused ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.12),
                width: _focused ? 2 : 1,
              ),
              boxShadow: _focused
                  ? <BoxShadow>[BoxShadow(color: kJuanchoGlow.withOpacity(0.5), blurRadius: 20)]
                  : null,
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
                key: ValueKey<String>('${t.key}_${m.id}_${m.status}_${m.goalsHome}_${m.goalsAway}'),
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
