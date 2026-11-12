/*
 * LTv Juancho - pantalla principal: saludo, reloj, barra de apps y brasas.
 * Este archivo es nuevo; no forma parte del proyecto original.
 *
 * Las apps de la barra se guardan en la categoria "Favorites" del launcher
 * (asi persisten sin tocar la base de datos). La primera vez se llenan con
 * Netflix, YouTube, YouTube Music, Crunchyroll, HBO Max, Downloader y hybdra
 * (si estan instaladas). El ultimo boton "+" permite agregar mas apps.
 * Mantener pulsado OK (o la tecla de menu) sobre una app abre sus opciones.
 *
 * Tambien: cascada de entrada, efecto "ola" al enfocar, saludo segun la hora,
 * brasas flotando y modo reposo (tras 60 s sin tocar nada queda solo el reloj).
 */

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/focus_ball_overlay.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/juancho_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _seedFlagKey = 'juancho_dock_seeded_v1';

// Apps que se colocan solas la primera vez (si estan instaladas).
const List<String> _defaultDockPackages = <String>[
  'com.netflix.ninja',
  'com.google.android.youtube.tv',
  'com.google.android.youtube.tvmusic',
  'com.crunchyroll.crunchyroid',
  'com.wbd.stream',
  'com.esaba.downloader',
];

const double _tileW = 144;
const double _tileH = 81;
const Duration _idleAfter = Duration(seconds: 60);

// ---------------------------------------------------------------------------
// Pantalla principal
// ---------------------------------------------------------------------------

class HomeDock extends StatefulWidget {
  const HomeDock({super.key});

  @override
  State<HomeDock> createState() => _HomeDockState();
}

class _HomeDockState extends State<HomeDock>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final FocusNode _addNode = FocusNode(debugLabel: 'dock-add');
  late final AnimationController _enter;

  int _focusIndex = -1;
  bool _idle = false;
  bool _justWoke = false;
  DateTime _lastKey = DateTime.now();
  Timer? _idleTimer;
  int _greetingSeed = 0;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkIdle());
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _enter.dispose();
    _addNode.dispose();
    super.dispose();
  }

  // Al volver al Home desde otra app: cascada y saludo de nuevo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _lastKey = DateTime.now();
      setState(() {
        _idle = false;
        _greetingSeed++;
      });
      _enter.forward(from: 0);
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      return false;
    }
    final bool wasIdle = _idle;
    if (!wasIdle) {
      _justWoke = false;
    }
    _lastKey = DateTime.now();
    if (wasIdle && mounted) {
      setState(() {
        _idle = false;
        _justWoke = true;
      });
    }
    return false; // nunca consume la tecla
  }

  void _checkIdle() {
    if (!mounted || _idle) {
      return;
    }
    final ModalRoute<dynamic>? route = _route;
    if (route != null && !route.isCurrent) {
      _lastKey = DateTime.now(); // hay un menu abierto: no es reposo
      return;
    }
    if (DateTime.now().difference(_lastKey) > _idleAfter) {
      setState(() => _idle = true);
    }
  }

  // La tecla que despierta del reposo no debe abrir una app a ciegas.
  void _guard(VoidCallback action) {
    if (_justWoke) {
      _justWoke = false;
      return;
    }
    action();
  }

  void _setFocus(int index, bool focused) {
    if (!mounted) {
      return;
    }
    if (focused) {
      if (_focusIndex != index) {
        setState(() => _focusIndex = index);
      }
    } else if (_focusIndex == index) {
      setState(() => _focusIndex = -1);
    }
  }

  Future<void> _seedIfNeeded() async {
    if (!mounted) {
      return;
    }
    final AppsService service = context.read<AppsService>();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_seedFlagKey) == true) {
        return;
      }
      for (final String pkg in _defaultDockPackages) {
        final App? app = service.getApp(pkg);
        if (app != null) {
          await service.addToFavorites(app);
        }
      }
      // hybdra: se busca por nombre porque no se conoce su paquete
      for (final App app in service.applications) {
        final String n = app.name.toLowerCase();
        if (n.contains('hybdra') || n.contains('hydra')) {
          await service.addToFavorites(app);
          break;
        }
      }
      await prefs.setBool(_seedFlagKey, true);
    } catch (_) {
      // si algo falla, la barra queda vacia y se puede llenar con "+"
    }
  }

  Category? _favorites(AppsService service) {
    for (final Category c in service.categories) {
      if (c.name == 'Favorites') {
        return c;
      }
    }
    return null;
  }

  Future<void> _showMenu(AppsService service, Category cat, App app, int index, int count) async {
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: const Color(0xEE1A1A1F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  app.name,
                  style: Theme.of(ctx).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                _MenuButton(icon: Icons.play_arrow_rounded, label: 'Abrir', value: 'open', autofocus: true),
                if (index > 0)
                  _MenuButton(icon: Icons.arrow_back_rounded, label: 'Mover a la izquierda', value: 'left'),
                if (index < count - 1)
                  _MenuButton(icon: Icons.arrow_forward_rounded, label: 'Mover a la derecha', value: 'right'),
                _MenuButton(icon: Icons.remove_circle_outline, label: 'Quitar de la barra', value: 'remove'),
                _MenuButton(icon: Icons.info_outline, label: 'Informacion de la app', value: 'info'),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    switch (choice) {
      case 'open':
        await service.launchApp(app);
        break;
      case 'left':
        service.reorderApplication(cat, index, index - 1);
        await service.saveApplicationOrderInCategory(cat);
        break;
      case 'right':
        service.reorderApplication(cat, index, index + 1);
        await service.saveApplicationOrderInCategory(cat);
        break;
      case 'remove':
        await service.removeFromFavorites(app);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _addNode.requestFocus();
          }
        });
        break;
      case 'info':
        await service.openAppInfo(app);
        break;
    }
  }

  Future<void> _showAddDialog(AppsService service, Category? cat) async {
    final Set<String> inDock = <String>{
      for (final App a in (cat?.applications ?? <App>[])) a.packageName,
    };
    final List<App> candidates = service.applications
        .where((App a) => !a.hidden && !inDock.contains(a.packageName))
        .toList();

    final App? picked = await showDialog<App>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: const Color(0xF0141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Agregar a la barra', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                Flexible(
                  child: candidates.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No hay mas apps para agregar.'),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: <Widget>[
                              for (int i = 0; i < candidates.length; i++)
                                _PickerItem(
                                  app: candidates[i],
                                  autofocus: i == 0,
                                  onPick: () => Navigator.of(ctx).pop(candidates[i]),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      await service.addToFavorites(picked);
    }
  }

  // Cada tarjeta entra subiendo y apareciendo, una detras de otra.
  Widget _cascade(int i, Widget child) {
    final double start = math.min(i * 0.07, 0.45);
    final Interval curve = Interval(start, math.min(start + 0.5, 1.0), curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: _enter,
      child: child,
      builder: (BuildContext context, Widget? ch) {
        final double v = curve.transform(_enter.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 36 * (1 - v)), child: ch),
        );
      },
    );
  }

  double _neighborScale(int index) {
    if (_focusIndex < 0) {
      return 1.0;
    }
    return (index - _focusIndex).abs() == 1 ? 1.07 : 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppsService>(
      builder: (BuildContext context, AppsService service, _) {
        final Category? cat = _favorites(service);
        final List<App> apps = <App>[
          if (cat != null)
            for (final App a in cat.applications)
              if (!a.hidden) a,
        ];

        final List<Widget> tiles = <Widget>[];
        for (int i = 0; i < apps.length; i++) {
          final App app = apps[i];
          tiles.add(
            _cascade(
              i,
              _DockTile(
                key: ValueKey<String>('dock_${app.packageName}'),
                autofocus: i == 0,
                neighborScale: _neighborScale(i),
                onFocusChanged: (bool f) => _setFocus(i, f),
                onSelect: () => _guard(() => service.launchApp(app)),
                onMenu: cat == null ? () {} : () => _showMenu(service, cat, app, i, apps.length),
                child: _AppFace(app: app),
              ),
            ),
          );
        }
        final int addIndex = apps.length;
        tiles.add(
          _cascade(
            addIndex,
            _DockTile(
              key: const ValueKey<String>('dock_add'),
              focusNode: _addNode,
              autofocus: apps.isEmpty,
              neighborScale: _neighborScale(addIndex),
              onFocusChanged: (bool f) => _setFocus(addIndex, f),
              onSelect: () => _guard(() => _showAddDialog(service, cat)),
              onMenu: () => _showAddDialog(service, cat),
              child: const _AddFace(),
            ),
          ),
        );

        return Stack(
          children: <Widget>[
            const Positioned.fill(
              child: IgnorePointer(child: RepaintBoundary(child: _Embers())),
            ),
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: _Greeting(key: ValueKey<int>(_greetingSeed)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: AnimatedSlide(
                      offset: Offset(0, _idle ? 1.25 : 0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOutCubic,
                      child: AnimatedScale(
                        scale: _idle ? 1.45 : 1.0,
                        alignment: Alignment.bottomLeft,
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOutCubic,
                        child: const _DockClock(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: _idle ? 0 : 1,
                    duration: const Duration(milliseconds: 600),
                    child: AnimatedSlide(
                      offset: Offset(0, _idle ? 0.35 : 0),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeInOutCubic,
                      child: SizedBox(
                        height: 150,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                          child: Row(children: tiles),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de la barra
// ---------------------------------------------------------------------------

/// Tarjeta de la barra: foco con brillo rojo, ola a las vecinas, rebote
/// cuando el balon la golpea y desplazamiento automatico de la barra.
class _DockTile extends StatefulWidget {
  const _DockTile({
    super.key,
    required this.child,
    required this.onSelect,
    required this.onMenu,
    required this.onFocusChanged,
    this.neighborScale = 1.0,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onSelect;
  final VoidCallback onMenu;
  final ValueChanged<bool> onFocusChanged;
  final double neighborScale;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_DockTile> createState() => _DockTileState();
}

class _DockTileState extends State<_DockTile> with SingleTickerProviderStateMixin {
  late final FocusNode _node;
  late final bool _ownsNode;
  late final AnimationController _dip;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode(debugLabel: 'dock-tile');
    _dip = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
    BallImpactBus.instance.addListener(_onImpact);
  }

  @override
  void dispose() {
    BallImpactBus.instance.removeListener(_onImpact);
    _dip.dispose();
    if (_ownsNode) {
      _node.dispose();
    }
    super.dispose();
  }

  void _onImpact() {
    if (!mounted) {
      return;
    }
    if (identical(BallImpactBus.instance.lastNode, _node)) {
      _dip.forward(from: 0);
    }
  }

  // cae hacia abajo con el golpe y regresa con rebote de resorte
  double _dipDy(double t) {
    const double depth = 10;
    if (t < 0.28) {
      return depth * Curves.easeOut.transform(t / 0.28);
    }
    final double u = (t - 0.28) / 0.72;
    return depth * (1 - Curves.elasticOut.transform(u));
  }

  void _onFocusChange(bool f) {
    if (!mounted) {
      return;
    }
    setState(() => _focused = f);
    widget.onFocusChanged(f);
    if (f) {
      // mantiene la tarjeta enfocada centrada dentro de la barra
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_node.hasFocus) {
          return;
        }
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double scale = _focused ? 1.16 : widget.neighborScale;
    return FocusKeyboardListener(
      onPressed: (key) {
        if (AppCardKeys.validationKeys.contains(key)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onLongPress: (key) {
        widget.onMenu();
        return KeyEventResult.handled;
      },
      builder: (BuildContext context) => Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: _onFocusChange,
        child: GestureDetector(
          onTap: widget.onSelect,
          child: AnimatedBuilder(
            animation: _dip,
            builder: (BuildContext context, Widget? child) {
              final double dy = _dip.isAnimating ? _dipDy(_dip.value) : 0;
              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.diagonal3Values(1, 1 - dy * 0.004, 1),
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: _tileW,
                  height: _tileH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _focused ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.14),
                      width: _focused ? 2.5 : 1,
                    ),
                    boxShadow: <BoxShadow>[
                      if (_focused)
                        BoxShadow(color: kJuanchoGlow.withOpacity(0.60), blurRadius: 30, spreadRadius: 2),
                      BoxShadow(
                        color: Colors.black.withOpacity(_focused ? 0.55 : 0.35),
                        blurRadius: _focused ? 20 : 10,
                        offset: Offset(0, _focused ? 10 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        widget.child,
                        // brillo suave arriba, da aspecto de cristal
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.center,
                                colors: <Color>[
                                  Colors.white.withOpacity(_focused ? 0.22 : 0.10),
                                  Colors.white.withOpacity(0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cara de una app: banner si tiene, si no el icono con el nombre.
class _AppFace extends StatefulWidget {
  const _AppFace({required this.app});

  final App app;

  @override
  State<_AppFace> createState() => _AppFaceState();
}

class _AppFaceState extends State<_AppFace> {
  late Future<(bool, Uint8List)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(bool, Uint8List)> _load() async {
    final AppsService service = context.read<AppsService>();
    try {
      final Uint8List banner = await service.getAppBanner(widget.app.packageName);
      if (banner.isNotEmpty) {
        return (true, banner);
      }
    } catch (_) {}
    try {
      final Uint8List icon = await service.getAppIcon(widget.app.packageName);
      return (false, icon);
    } catch (_) {
      return (false, Uint8List(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, Uint8List)>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<(bool, Uint8List)> snap) {
        final (bool isBanner, Uint8List bytes) = snap.data ?? (false, Uint8List(0));
        if (isBanner && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        }
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF2B2B33), Color(0xFF15151A)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (bytes.isNotEmpty)
                Image.memory(bytes, width: 38, height: 38, gaplessPlayback: true)
              else
                const Icon(Icons.apps_rounded, size: 34, color: Colors.white70),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddFace extends StatelessWidget {
  const _AddFace();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withOpacity(0.16),
            Colors.white.withOpacity(0.06),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.add_rounded, size: 44, color: Colors.white),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.value,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TextButton(
        autofocus: autofocus,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        onPressed: () => Navigator.of(context).pop(value),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          ],
        ),
      ),
    );
  }
}

class _PickerItem extends StatefulWidget {
  const _PickerItem({required this.app, required this.onPick, this.autofocus = false});

  final App app;
  final VoidCallback onPick;
  final bool autofocus;

  @override
  State<_PickerItem> createState() => _PickerItemState();
}

class _PickerItemState extends State<_PickerItem> {
  late Future<Uint8List> _icon;

  @override
  void initState() {
    super.initState();
    _icon = context.read<AppsService>().getAppIcon(widget.app.packageName).catchError((_) => Uint8List(0));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 118,
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onPick,
        borderRadius: BorderRadius.circular(14),
        focusColor: Colors.white.withOpacity(0.22),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FutureBuilder<Uint8List>(
                future: _icon,
                builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                  final Uint8List? bytes = snap.data;
                  if (bytes != null && bytes.isNotEmpty) {
                    return Image.memory(bytes, width: 52, height: 52, gaplessPlayback: true);
                  }
                  return const SizedBox(width: 52, height: 52, child: Icon(Icons.apps_rounded, color: Colors.white54));
                },
              ),
              const SizedBox(height: 8),
              Text(
                widget.app.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reloj
// ---------------------------------------------------------------------------

/// Reloj grande y elegante, encima de la barra.
class _DockClock extends StatefulWidget {
  const _DockClock();

  @override
  State<_DockClock> createState() => _DockClockState();
}

class _DockClockState extends State<_DockClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime n = DateTime.now();
      if (!mounted) {
        return;
      }
      if (n.minute != _now.minute || n.hour != _now.hour || n.day != _now.day) {
        setState(() => _now = n);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(String pattern, DateTime t) {
    try {
      return DateFormat(pattern, Platform.localeName).format(t);
    } catch (_) {
      try {
        return DateFormat(pattern).format(t);
      } catch (_) {
        return '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final String time = _fmt(settings.timeFormat, _now);
    final String date = _fmt(settings.dateFormat, _now).toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          time,
          style: const TextStyle(
            fontSize: 72,
            height: 1.0,
            fontWeight: FontWeight.w200,
            letterSpacing: -1.5,
            color: Colors.white,
            shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 3))],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(color: kJuanchoGlow, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Text(
              date,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.4,
                color: Colors.white.withOpacity(0.88),
                shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Saludo "caldera del diablo"
// ---------------------------------------------------------------------------

class _Greeting extends StatefulWidget {
  const _Greeting({super.key});

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> with SingleTickerProviderStateMixin {
  static const double _totalMs = 8600;
  static int _lastPhrase = -1;

  late final AnimationController _c;
  late final String _saludo;
  late final String _frase;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _saludo = _saludoPara(now);
    _frase = _fraseNueva(now);
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: _totalMs.toInt()))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static String _saludoPara(DateTime t) {
    final int h = t.hour;
    if (h < 5) {
      return 'Re madrugado, Juancho';
    }
    if (h < 12) {
      return 'Buenos días, Juancho';
    }
    if (h < 18) {
      return 'Buenas tardes, Juancho';
    }
    return 'Buenas noches, Juancho';
  }

  // {H} = "Son las 10:42 p. m." / "Es la 1:05 a. m."
  static String _horaCompleta(DateTime t) {
    final int h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final String min = t.minute.toString().padLeft(2, '0');
    final String suf = t.hour < 12 ? 'a. m.' : 'p. m.';
    final String art = h12 == 1 ? 'Es la' : 'Son las';
    return '$art $h12:$min $suf';
  }

  static String _fraseNueva(DateTime t) {
    final int h = t.hour;
    final List<String> madrugada = <String>[
      '{H}, VJ… ¿sigues despierto, parce?',
      '{H} y la caldera sigue prendida, VJ',
      '{H}, VJ. ¿Y ese desvelo, parcero?',
      '{H}. A esta hora solo quedamos los duros, parce',
      '{H}. Eso es berraquera, parce: siga dándole',
    ];
    final List<String> manana = <String>[
      '{H}, VJ. Arriba, que el día está para comérselo',
      'Qué más, Juancho. {H}: a darle con toda',
      '{H} y ya andamos de pie. Eso, parce',
      '{H}. Tinto, pilas y que arda el día',
    ];
    final List<String> tarde = <String>[
      '{H}, VJ. ¿Qué más, parce, cómo va la tarde?',
      '{H}. Hágale, que la tarde está para un buen parche',
      '{H}, Juancho. Un descansito bien merecido',
      '{H} y la caldera tibia, parcero',
    ];
    final List<String> noche = <String>[
      '{H}, VJ. Prenda la caldera, que arranca el parche',
      '{H}, Juancho. Hoy hay plan: sofá, pantalla y cero afán',
      'Qué nota la noche, VJ. {H}',
      '{H}, parcero. ¡Que arda la noche!',
    ];
    final List<String> finde = <String>[
      '¡Parche de viernes, Juancho! {H}',
      '{H}. Fin de semana, VJ: a prender esa caldera',
    ];

    List<String> lista;
    if (h < 5) {
      lista = madrugada;
    } else if (h < 12) {
      lista = manana;
    } else if (h < 18) {
      lista = tarde;
    } else {
      lista = noche;
      if (t.weekday == DateTime.friday || t.weekday == DateTime.saturday) {
        lista = <String>[...noche, ...finde];
      }
    }
    final math.Random rnd = math.Random();
    int i = rnd.nextInt(lista.length);
    if (lista.length > 1 && i == _lastPhrase) {
      i = (i + 1) % lista.length;
    }
    _lastPhrase = i;
    return lista[i].replaceAll('{H}', _horaCompleta(t));
  }

  @override
  Widget build(BuildContext context) {
    final List<String> chars = _saludo.split('');
    return SizedBox(
      height: 96,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final double t = _c.value * _totalMs;
          final double fadeOut = 1 - ((t - 7700) / 900).clamp(0.0, 1.0).toDouble();
          if (fadeOut <= 0) {
            return const SizedBox.shrink();
          }
          final double p2 = ((t - 1500) / 800).clamp(0.0, 1.0).toDouble();
          final double e2 = Curves.easeOutCubic.transform(p2);
          return Opacity(
            opacity: fadeOut,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < chars.length; i++) _letter(chars[i], i, chars.length, t),
                  ],
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: e2,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - e2)),
                    child: Text(
                      _frase,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.92),
                        shadows: const <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Cada letra sube con brillo de brasa que parpadea.
  Widget _letter(String ch, int i, int n, double t) {
    final double start = i * (1100.0 / n);
    final double p = ((t - start) / 450).clamp(0.0, 1.0).toDouble();
    final double e = Curves.easeOutCubic.transform(p);
    final double flick = math.sin(t / 110 + i * 0.9);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 24 * (1 - e)),
        child: Text(
          ch,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: <Shadow>[
              Shadow(
                color: kJuanchoGlow.withOpacity((0.60 + 0.25 * flick).clamp(0.0, 1.0).toDouble()),
                blurRadius: 16 + 7 * flick,
              ),
              const Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brasas
// ---------------------------------------------------------------------------

class _Embers extends StatefulWidget {
  const _Embers();

  @override
  State<_Embers> createState() => _EmbersState();
}

class _EmbersState extends State<_Embers> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _EmberPainter(_c), size: Size.infinite);
  }
}

class _EmberPainter extends CustomPainter {
  _EmberPainter(this.animation) : super(repaint: animation) {
    final math.Random rnd = math.Random(5);
    for (int i = 0; i < 26; i++) {
      _x.add(rnd.nextDouble());
      _phase.add(rnd.nextDouble());
      _loops.add(rnd.nextBool() ? 1 : 2);
      _size.add(1.3 + rnd.nextDouble() * 2.4);
      _sway.add(8 + rnd.nextDouble() * 22);
    }
  }

  final Animation<double> animation;
  final List<double> _x = <double>[];
  final List<double> _phase = <double>[];
  final List<int> _loops = <int>[];
  final List<double> _size = <double>[];
  final List<double> _sway = <double>[];

  @override
  void paint(Canvas canvas, Size size) {
    final double t = animation.value;
    final Paint paint = Paint();
    for (int i = 0; i < _x.length; i++) {
      final double prog = (_phase[i] + t * _loops[i]) % 1.0;
      final double x = _x[i] * size.width + math.sin(prog * math.pi * 3 + i) * _sway[i];
      final double y = size.height * (1.02 - 0.80 * prog);
      final double a = math.sin(prog * math.pi).clamp(0.0, 1.0).toDouble() * 0.85;
      final Color col = Color.lerp(kJuanchoEmber, kJuanchoGlow, prog) ?? kJuanchoGlow;
      final double rad = _size[i] * (1 - 0.45 * prog);
      paint.color = col.withOpacity(a * 0.22);
      canvas.drawCircle(Offset(x, y), rad * 2.6, paint);
      paint.color = col.withOpacity(a);
      canvas.drawCircle(Offset(x, y), rad, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter oldDelegate) => false;
}
