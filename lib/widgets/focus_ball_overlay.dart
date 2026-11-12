/*
 * LTv Juancho - balon de cuero que salta entre apps.
 * Este archivo es nuevo; no forma parte del proyecto original.
 *
 * Funciona asi: escucha cuando el foco del control remoto cambia de una tarjeta
 * a otra, y hace saltar un balon de cuero en arco hasta la nueva tarjeta
 * (con dos rebotes pequenos al caer). Al aterrizar avisa a la tarjeta
 * (BallImpactBus) para que "caiga" con el golpe, y despues el balon se
 * desvanece: solo se ve mientras te mueves.
 *
 * Para apagarlo: poner kFocusBallEnabled en false.
 */

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const bool kFocusBallEnabled = true;

/// Aviso de "el balon aterrizo sobre este foco". Las tarjetas lo escuchan.
class BallImpactBus extends ChangeNotifier {
  BallImpactBus._();

  static final BallImpactBus instance = BallImpactBus._();

  FocusNode? lastNode;

  void notifyLanded(FocusNode node) {
    lastNode = node;
    notifyListeners();
  }
}

class FocusBallOverlay extends StatefulWidget {
  const FocusBallOverlay({super.key});

  @override
  State<FocusBallOverlay> createState() => _FocusBallOverlayState();
}

class _FocusBallOverlayState extends State<FocusBallOverlay>
    with SingleTickerProviderStateMixin {
  static const double _diameter = 66;
  static const double _hopMs = 480;
  static const double _bounce1Ms = 190;
  static const double _bounce2Ms = 130;
  static const double _fadeMs = 230;
  static const Duration _awake = Duration(milliseconds: 1400);

  late final Ticker _ticker;
  Duration _now = Duration.zero;
  Duration _activeUntil = Duration.zero;

  FocusNode? _node;
  Offset? _pos;
  Offset _hopFrom = Offset.zero;
  double _hopStartMs = 0;
  bool _hopping = false;
  bool _landed = false;
  double _arc = 80;
  double _angle = 0;
  double _alpha = 0;
  double _squash = 0;
  double _shownAlpha = -1;
  double _shownSquash = -1;
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

  // El balon cae sobre el borde superior de la tarjeta, un poco metido.
  Offset _restingPoint(Rect rect) => Offset(
        rect.center.dx,
        math.max(rect.top - _diameter / 2 + 6, _diameter / 2 + 4),
      );

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
    _arc = ((target - start).distance * 0.30).clamp(40.0, 130.0).toDouble();
    _node = node;
    _hopping = true;
    _landed = false;
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
      double squash = 0;
      double alpha = _hopping ? 1.0 : 0.0;

      if (_hopping) {
        final double ms = _now.inMicroseconds / 1000.0 - _hopStartMs;
        if (ms < _hopMs) {
          final double t = ms / _hopMs;
          final double e = Curves.easeInOut.transform(t);
          final double x = _hopFrom.dx + (target.dx - _hopFrom.dx) * e;
          final double yLine = _hopFrom.dy + (target.dy - _hopFrom.dy) * t;
          final double y = yLine - _arc * 4 * t * (1 - t);
          next = Offset(x, y);
          alpha = (ms / 70.0).clamp(0.0, 1.0).toDouble();
        } else {
          if (!_landed) {
            _landed = true;
            BallImpactBus.instance.notifyLanded(node);
          }
          final double b = ms - _hopMs;
          if (b < _bounce1Ms) {
            final double u = b / _bounce1Ms;
            bounce = -18 * 4 * u * (1 - u);
            squash = math.pow(1 - 4 * u * (1 - u), 5).toDouble();
          } else if (b < _bounce1Ms + _bounce2Ms) {
            final double u = (b - _bounce1Ms) / _bounce2Ms;
            bounce = -8 * 4 * u * (1 - u);
            squash = 0.5 * math.pow(1 - 4 * u * (1 - u), 5).toDouble();
          } else {
            final double f = (b - _bounce1Ms - _bounce2Ms) / _fadeMs;
            if (f >= 1) {
              _hopping = false;
              alpha = 0;
            } else {
              alpha = 1 - f;
            }
          }
        }
      }

      final Offset draw = Offset(next.dx, next.dy + bounce);
      final Offset? prev = _pos;
      final bool moved = prev == null || (draw - prev).distance > 0.2;
      final bool changed = moved ||
          (alpha - _shownAlpha).abs() > 0.01 ||
          (squash - _shownSquash).abs() > 0.01;
      if (changed) {
        if (prev != null) {
          _angle += (draw.dx - prev.dx) / (_diameter / 2);
        }
        _alpha = alpha;
        _squash = squash;
        _shownAlpha = alpha;
        _shownSquash = squash;
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
    if (pos == null || _alpha <= 0.01) {
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
            child: Opacity(
              opacity: _alpha,
              child: RepaintBoundary(
                child: CustomPaint(painter: _BallPainter(_angle, _squash)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Balon antiguo de cuero: paneles cosidos (3 franjas de 6), cuero gastado
/// color coñac, agujetas cruzadas en un panel y brillo de luz.
class _BallPainter extends CustomPainter {
  _BallPainter(this.angle, this.squash);

  final double angle;
  final double squash;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;

    canvas.save();
    // aplastamiento al tocar la tarjeta (pivote en la base del balon)
    canvas.translate(c.dx, c.dy + r);
    canvas.scale(1 + 0.18 * squash, 1 - 0.18 * squash);
    canvas.translate(-c.dx, -(c.dy + r));

    // sombra
    canvas.drawCircle(
      c + Offset(0, r * 0.14),
      r * 0.96,
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.2),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // cuero base con volumen
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.05,
          colors: <Color>[
            Color(0xFFE8B97C),
            Color(0xFFC98B4B),
            Color(0xFF93572A),
            Color(0xFF4F2B12),
          ],
          stops: <double>[0.0, 0.40, 0.76, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // todo lo que sigue gira con el balon
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);

    // manchas y desgaste del cuero
    final math.Random rnd = math.Random(7);
    for (int i = 0; i < 18; i++) {
      final double a = rnd.nextDouble() * 2 * math.pi;
      final double d = math.sqrt(rnd.nextDouble()) * r * 0.92;
      final double rad = r * (0.07 + rnd.nextDouble() * 0.12);
      final bool dark = rnd.nextBool();
      canvas.drawCircle(
        Offset(math.cos(a) * d, math.sin(a) * d),
        rad,
        Paint()
          ..color = (dark ? const Color(0xFF2E1608) : const Color(0xFFFFE6B8))
              .withOpacity(dark ? 0.16 : 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.6),
      );
    }

    // costuras de los paneles: dos lineas de "ecuador" y meridianos
    final Paint seam = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF2B1507)
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;
    final Paint seamLight = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFFF3D6A4).withOpacity(0.45)
      ..strokeWidth = r * 0.02
      ..strokeCap = StrokeCap.round;

    void line(Path path) {
      canvas.drawPath(path, seam);
      canvas.save();
      canvas.translate(r * 0.03, r * 0.03);
      canvas.drawPath(path, seamLight);
      canvas.restore();
    }

    // franjas horizontales (curvadas como vistas desde arriba)
    for (final double y in <double>[-0.34, 0.34]) {
      final double half = math.sqrt(math.max(0.0, 1 - y * y)) * r;
      final Path p = Path()
        ..moveTo(-half * 1.05, y * r)
        ..quadraticBezierTo(0, y * r + r * 0.20, half * 1.05, y * r);
      line(p);
    }
    // meridianos: forman los 6 paneles de cada franja
    for (final double w in <double>[0.0, 0.42, 0.80]) {
      if (w == 0.0) {
        line(Path()
          ..moveTo(0, -r)
          ..lineTo(0, r));
      } else {
        for (final int sgn in <int>[-1, 1]) {
          final Path p = Path()
            ..moveTo(0, -r)
            ..quadraticBezierTo(sgn * w * r * 1.9, 0, 0, r);
          line(p);
        }
      }
    }

    // agujetas: ranura en el panel central con hilo cruzado
    final RRect slit = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -r * 0.02), width: r * 0.11, height: r * 0.50),
      Radius.circular(r * 0.05),
    );
    canvas.drawRRect(slit, Paint()..color = const Color(0xFF1E0E05));
    final Paint lace = Paint()
      ..color = const Color(0xFFF7E8C8)
      ..strokeWidth = r * 0.045
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 5; i++) {
      final double y = -r * 0.23 + i * r * 0.115;
      canvas.drawLine(Offset(-r * 0.12, y - r * 0.035), Offset(r * 0.12, y + r * 0.035), lace);
      canvas.drawLine(Offset(-r * 0.12, y + r * 0.035), Offset(r * 0.12, y - r * 0.035), lace);
    }

    canvas.restore(); // fin de lo que gira

    // sombreado de borde y brillo: no giran, para que se vea redondo
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 1.0,
          colors: <Color>[
            Color(0x00000000),
            Color(0x00000000),
            Color(0x88000000),
          ],
          stops: <double>[0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c + Offset(-r * 0.38, -r * 0.42),
      r * 0.28,
      Paint()
        ..color = const Color(0x77FFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    canvas.restore(); // fin del recorte circular
    canvas.restore(); // fin del aplastamiento
  }

  @override
  bool shouldRepaint(covariant _BallPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.squash != squash;
}
