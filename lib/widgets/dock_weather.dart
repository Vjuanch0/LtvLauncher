/*
 * LTv Juancho - clima chico junto al reloj (Open-Meteo, sin clave).
 * Archivo nuevo. Ciudad fija: Bogota. Si no hay internet, no se muestra.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const double _lat = 4.711;
const double _lon = -74.0721;

class DockWeatherChip extends StatefulWidget {
  const DockWeatherChip({super.key});

  @override
  State<DockWeatherChip> createState() => _DockWeatherChipState();
}

class _DockWeatherChipState extends State<DockWeatherChip> {
  Timer? _timer;
  double? _temp;
  int _code = 0;
  bool _isDay = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final HttpClient client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final Uri uri = Uri.https('api.open-meteo.com', '/v1/forecast', <String, String>{
        'latitude': '$_lat',
        'longitude': '$_lon',
        'current': 'temperature_2m,weather_code,is_day',
        'timezone': 'auto',
      });
      final HttpClientRequest req = await client.getUrl(uri);
      final HttpClientResponse res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return;
      }
      final String body = await res.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        return;
      }
      final Object? cur = decoded['current'];
      if (cur is! Map) {
        return;
      }
      final Object? t = cur['temperature_2m'];
      final Object? c = cur['weather_code'];
      final Object? d = cur['is_day'];
      if (t is! num || !mounted) {
        return;
      }
      setState(() {
        _temp = t.toDouble();
        _code = c is num ? c.toInt() : 0;
        _isDay = d is num ? d.toInt() == 1 : true;
      });
    } catch (_) {
      // sin internet: se queda con el ultimo dato (o nada)
    } finally {
      client.close(force: true);
    }
  }

  IconData get _icon {
    final int c = _code;
    if (c == 0) {
      return _isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
    }
    if (c == 1 || c == 2) {
      return Icons.cloud_queue_rounded;
    }
    if (c == 3) {
      return Icons.cloud_rounded;
    }
    if (c == 45 || c == 48) {
      return Icons.blur_on_rounded;
    }
    if (c >= 71 && c <= 77) {
      return Icons.ac_unit_rounded;
    }
    if (c >= 95) {
      return Icons.flash_on_rounded;
    }
    return Icons.water_drop_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final double? t = _temp;
    if (t == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          _icon,
          size: 22,
          color: Colors.white.withOpacity(0.92),
          shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
        ),
        const SizedBox(width: 8),
        Text(
          '${t.round()}°',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            color: Colors.white.withOpacity(0.95),
            shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'BOGOTÁ',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}
