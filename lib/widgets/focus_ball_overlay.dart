/*
 * LTv Juancho - balon que salta entre apps.
 * Este archivo es nuevo; no forma parte del proyecto original.
 *
 * Funciona asi: escucha cuando el foco del control remoto cambia de una tarjeta
 * a otra, y hace saltar un balon de futbol en arco hasta la nueva tarjeta
 * (con dos rebotes pequenos al caer). Todo vive en una capa transparente
 * encima de la pantalla, asi que no toca el resto del launcher.
 *
 * Para apagarlo: poner kFocusBallEnabled en false.
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const bool kFocusBallEnabled = true;

class FocusBallOverlay extends StatefulWidget {
  const FocusBallOverlay({super.key});

  @override
  State<FocusBallOverlay> createState() => _FocusBallOverlayState();
}

class _FocusBallOverlayState extends State<FocusBallOverlay>
    with SingleTickerProviderStateMixin {
  static const double _diameter = 38;
  static const double _hopMs = 480;
  static const double _bounce1Ms = 200;
  static const double _bounce2Ms = 140;
  static const Duration _awake = Duration(milliseconds: 1100);

  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _activeUntil = Duration.zero;

  FocusNode? _node;
  Offset? _pos;
  Offset _hopFrom = Offset.zero;
  double _hopStartMs = 0;
  bool _hopping = false;
  double _arc = 80;
  double _angle = 0;
  Size _screen = const Size(1920, 1080);
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    FocusManager.instance.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocusChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    _ticker.dispose();
    super.dispose();
  }

  Rect? _rectOf(FocusNode node) {
    try {
      final BuildContext? ctx = node.context;
      if (ctx == null || !ctx.mounted) {
        return null;
      }
      final RenderObject? ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
        return null;
      }
      final Offset topLeft = ro.localToGlobal(Offset.zero);
      return topLeft & ro.size;
    } catch (_) {
      return null;
    }
  }

  Offset _restingPoint(Rect rect) =>
      Offset(rect.center.dx, rect.top - _diameter / 2 - 1);

  void _wake() {
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _ticker.start();
    }
    _activeUntil = _now + _awake;
  }

  void _onFocusChanged() {
    if (!mounted) {
      return;
    }
    final ModalRoute<dynamic>? route = _route;
    if (route != null && !route.isCurrent) {
      return;
    }
    final FocusNode? node = FocusManager.instance.primaryFocus;
    if (node == null || identical(node, _node)) {
      return;
    }
    final Rect? rect = _rectOf(node);
    if (rect == null) {
      return;
    }
    if (rect.width < 40 ||
        rect.height < 30 ||
        rect.width > _screen.width * 0.6 ||
        rect.height > _screen.height * 0.5) {
      return;
    }

    final Offset target = _restingPoint(rect);
    final Offset start = _pos ?? Offset(target.dx, -_diameter);
    _wake();
    _hopFrom = start;
    _arc = ((target - start).distance * 0.28).clamp(36.0, 120.0).toDouble();
    _node = node;
    _hopping = true;
    _hopStartMs = _now.inMicroseconds / 1000.0;
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    final FocusNode? node = _node;
    if (node == null) {
      _ticker.stop();
      return;
    }
    final Rect? rect = _rectOf(node);
    if (rect != null) {
      final Offset target = _restingPoint(rect);
      Offset next = target;
      double bounce = 0;

      if (_hopping) {
        final double ms = _now.inMicroseconds / 1000.0 - _hopStartMs;
        if (ms < _hopMs) {
          final double t = ms / _hopMs;
          final double e = Curves.easeInOut.transform(t);
          final double x = _hopFrom.dx + (target.dx - _hopFrom.dx) * e;
          final double yLine = _hopFrom.dy + (target.dy - _hopFrom.dy) * t;
          final double y = yLine - _arc * 4 * t * (1 - t);
          next = Offset(x, y);
        } else {
          final double b = ms - _hopMs;
          if (b < _bounce1Ms) {
            final double u = b / _bounce1Ms;
            bounce = -16 * 4 * u * (1 - u);
          } else if (b < _bounce1Ms + _bounce2Ms) {
            final double u = (b - _bounce1Ms) / _bounce2Ms;
            bounce = -7 * 4 * u * (1 - u);
          } else {
            _hopping = false;
          }
        }
      }

      final Offset draw = Offset(next.dx, next.dy + bounce);
      final Offset? prev = _pos;
      if (prev == null || (draw - prev).distance > 0.2) {
        if (prev != null) {
          _angle += (draw.dx - prev.dx) / (_diameter / 2);
        }
        setState(() {
          _pos = draw;
        });
      }
    } else {
      _hopping = false;
    }

    if (!_hopping && _now > _activeUntil) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.sizeOf(context);
    final Offset? pos = _pos;
    if (pos == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: pos.dx - _diameter / 2,
            top: pos.dy - _diameter / 2,
            width: _diameter,
            height: _diameter,
            child: RepaintBoundary(
              child: CustomPaint(painter: _BallPainter(_angle)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.angle);

  final double angle;

  Path _pentagon(double radius, double startAngle) {
    final Path path = Path();
    for (int k = 0; k < 5; k++) {
      final double a = startAngle + k * 2 * math.pi / 5;
      final double x = math.cos(a) * radius;
      final double y = math.sin(a) * radius;
      if (k == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;

    // sombra
    canvas.drawCircle(
      c + const Offset(0, 4),
      r * 0.95,
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFFFFF));

    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);

    final Paint black = Paint()..color = const Color(0xFF151515);
    final Paint seam = Paint()
      ..color = const Color(0xFF151515)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08;

    canvas.drawPath(_pentagon(r * 0.34, -math.pi / 2), black);
    for (int i = 0; i < 5; i++) {
      final double a = -math.pi / 2 + i * 2 * math.pi / 5;
      canvas.drawLine(
        Offset(math.cos(a) * r * 0.34, math.sin(a) * r * 0.34),
        Offset(math.cos(a) * r * 0.66, math.sin(a) * r * 0.66),
        seam,
      );
      canvas.save();
      canvas.translate(math.cos(a) * r * 1.0, math.sin(a) * r * 1.0);
      canvas.drawPath(_pentagon(r * 0.36, a + math.pi), black);
      canvas.restore();
    }

    // brillo para que se vea redondo
    canvas.rotate(-angle);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.45),
          radius: 1.0,
          colors: const <Color>[Color(0x00FFFFFF), Color(0x44000000)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BallPainter oldDelegate) =>
      oldDelegate.angle != angle;
}
