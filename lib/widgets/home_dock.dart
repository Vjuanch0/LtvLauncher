/*
 * LTv Juancho - barra inferior con las apps importantes + reloj.
 * Este archivo es nuevo; no forma parte del proyecto original.
 *
 * Las apps de la barra se guardan en la categoria "Favorites" del launcher
 * (asi persisten sin tocar la base de datos). La primera vez se llenan con
 * Netflix, YouTube, YouTube Music, Crunchyroll, HBO Max, Downloader y hybdra
 * (si estan instaladas). El ultimo boton "+" permite agregar mas apps.
 * Mantener pulsado OK (o la tecla de menu) sobre una app abre sus opciones.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/focus_ball_overlay.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
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

const double _tileW = 172;
const double _tileH = 97;

class HomeDock extends StatefulWidget {
  const HomeDock({super.key});

  @override
  State<HomeDock> createState() => _HomeDockState();
}

class _HomeDockState extends State<HomeDock> {
  final FocusNode _addNode = FocusNode(debugLabel: 'dock-add');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedIfNeeded());
  }

  @override
  void dispose() {
    _addNode.dispose();
    super.dispose();
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
            _DockTile(
              key: ValueKey<String>('dock_${app.packageName}'),
              autofocus: i == 0,
              onSelect: () => service.launchApp(app),
              onMenu: cat == null ? () {} : () => _showMenu(service, cat, app, i, apps.length),
              child: _AppFace(app: app),
            ),
          );
        }
        tiles.add(
          _DockTile(
            key: const ValueKey<String>('dock_add'),
            focusNode: _addNode,
            autofocus: apps.isEmpty,
            onSelect: () => _showAddDialog(service, cat),
            onMenu: () => _showAddDialog(service, cat),
            child: const _AddFace(),
          ),
        );

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(left: 44),
              child: _DockClock(),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.fromLTRB(30, 20, 30, 20),
                child: Row(children: tiles),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}

/// Tarjeta de la barra: foco con brillo, "cae" cuando el balon la golpea.
class _DockTile extends StatefulWidget {
  const _DockTile({
    super.key,
    required this.child,
    required this.onSelect,
    required this.onMenu,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onSelect;
  final VoidCallback onMenu;
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
    const double depth = 12;
    if (t < 0.28) {
      return depth * Curves.easeOut.transform(t / 0.28);
    }
    final double u = (t - 0.28) / 0.72;
    return depth * (1 - Curves.elasticOut.transform(u));
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
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
        onFocusChange: (bool f) {
          if (mounted) {
            setState(() => _focused = f);
          }
        },
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
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: AnimatedScale(
                scale: _focused ? 1.14 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _tileW,
                  height: _tileH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _focused ? Colors.white.withOpacity(0.92) : Colors.white.withOpacity(0.14),
                      width: _focused ? 2.5 : 1,
                    ),
                    boxShadow: <BoxShadow>[
                      if (_focused)
                        BoxShadow(color: accent.withOpacity(0.45), blurRadius: 28, spreadRadius: 1),
                      BoxShadow(
                        color: Colors.black.withOpacity(_focused ? 0.55 : 0.35),
                        blurRadius: _focused ? 20 : 10,
                        offset: Offset(0, _focused ? 10 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
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
                                  Colors.white.withOpacity(_focused ? 0.20 : 0.10),
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
                Image.memory(bytes, width: 44, height: 44, gaplessPlayback: true)
              else
                const Icon(Icons.apps_rounded, size: 40, color: Colors.white70),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
        child: Icon(Icons.add_rounded, size: 48, color: Colors.white),
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
    final Color accent = Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          time,
          style: const TextStyle(
            fontSize: 76,
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
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
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
