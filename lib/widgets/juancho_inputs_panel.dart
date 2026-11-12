/*
 * LTv Juancho - panel de entradas (HDMI, antena, AV).
 * Archivo nuevo. Atras solo cierra el panel.
 */

import 'package:flauncher/models/tv_input.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/widgets/juancho_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

Future<void> showJuanchoInputsPanel(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Entradas',
    barrierColor: Colors.black.withOpacity(0.62),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) => const _InputsSheet(),
    transitionBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b, Widget child) {
      final Animation<double> curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _InputsSheet extends StatelessWidget {
  const _InputsSheet();

  @override
  Widget build(BuildContext context) {
    final TvInputsService service = context.watch<TvInputsService>();
    final List<TvInput> inputs = service.inputs;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 860),
          padding: const EdgeInsets.fromLTRB(32, 26, 32, 30),
          decoration: BoxDecoration(
            color: const Color(0xE6121216),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
            boxShadow: <BoxShadow>[
              BoxShadow(color: kJuanchoGlow.withOpacity(0.18), blurRadius: 60, spreadRadius: 2),
              const BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(color: kJuanchoGlow, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Entradas',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, letterSpacing: 1.2, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    'Atrás para cerrar',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (inputs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    'No se detectaron entradas',
                    style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.7)),
                  ),
                )
              else
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: <Widget>[
                    for (int i = 0; i < inputs.length; i++)
                      _InputTile(
                        input: inputs[i],
                        autofocus: i == 0,
                        onPick: () {
                          Navigator.of(context).pop();
                          service.switchInput(inputs[i].id);
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputTile extends StatefulWidget {
  const _InputTile({required this.input, required this.onPick, this.autofocus = false});

  final TvInput input;
  final VoidCallback onPick;
  final bool autofocus;

  @override
  State<_InputTile> createState() => _InputTileState();
}

class _InputTileState extends State<_InputTile> {
  bool _focused = false;

  IconData get _icon {
    switch (widget.input.type) {
      case TvInputType.hdmi:
        return Icons.settings_input_hdmi_rounded;
      case TvInputType.tuner:
        return Icons.settings_input_antenna_rounded;
      case TvInputType.av:
        return Icons.settings_input_component_rounded;
      default:
        return Icons.input_rounded;
    }
  }

  String get _kind {
    switch (widget.input.type) {
      case TvInputType.hdmi:
        return 'HDMI';
      case TvInputType.tuner:
        return 'ANTENA';
      case TvInputType.av:
        return 'AV';
      default:
        return 'ENTRADA';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onPick();
          return null;
        }),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
          widget.onPick();
          return null;
        }),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (bool f) => setState(() => _focused = f),
        child: GestureDetector(
          onTap: widget.onPick,
          child: AnimatedScale(
            scale: _focused ? 1.07 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 244,
              height: 112,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.white.withOpacity(_focused ? 0.20 : 0.08),
                    Colors.white.withOpacity(_focused ? 0.08 : 0.03),
                  ],
                ),
                border: Border.all(
                  color: _focused ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.14),
                  width: _focused ? 2.5 : 1,
                ),
                boxShadow: _focused
                    ? <BoxShadow>[BoxShadow(color: kJuanchoGlow.withOpacity(0.55), blurRadius: 26, spreadRadius: 1)]
                    : null,
              ),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _focused ? kJuanchoGlow.withOpacity(0.9) : Colors.white.withOpacity(0.10),
                    ),
                    child: Icon(_icon, size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _kind,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.input.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
