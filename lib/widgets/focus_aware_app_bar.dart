import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/inputs_panel.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'daily_data_usage_widget.dart';
import 'juancho_theme.dart';
import 'date_time_widget.dart';
import 'network_widget.dart';
import 'weather_status_bar_widget.dart';

class FocusAwareAppBar extends StatefulWidget implements PreferredSizeWidget
{
  const FocusAwareAppBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return FocusAwareAppBarState();
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

class FocusAwareAppBarState extends State<FocusAwareAppBar>
{
  bool focused = false;
  late FocusNode _settingsFocusNode;
  late FocusNode _inputsFocusNode;
  late FocusNode _notificationsFocusNode;
  late FocusNode _weatherFocusNode;

  FocusNode get settingsFocusNode => _settingsFocusNode;
  FocusNode get inputsFocusNode => _inputsFocusNode;
  FocusNode get notificationsFocusNode => _notificationsFocusNode;
  FocusNode get weatherFocusNode => _weatherFocusNode;

  @override
  void initState() {
    super.initState();
    _settingsFocusNode = FocusNode();
    _inputsFocusNode = FocusNode();
    _notificationsFocusNode = FocusNode();
    _weatherFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _settingsFocusNode.dispose();
    _inputsFocusNode.dispose();
    _notificationsFocusNode.dispose();
    _weatherFocusNode.dispose();
    super.dispose();
  }

  void focusSettings() {
    _settingsFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, bool>(
      selector: (_, settings) => settings.autoHideAppBarEnabled,
      builder: (context, autoHide, widget) {
        if (autoHide) {
          return Focus(
            canRequestFocus: false,
            child: AnimatedContainer(
              curve: Curves.decelerate,
              duration: Duration(milliseconds: 150),
              height: focused ? kToolbarHeight : 0,
              child: widget!
            ),
            onFocusChange: (hasFocus) {
              this.setState(() {
                focused = hasFocus;
              });
            }
          );
        }

        return widget!;
      },
      child: RepaintBoundary(
        child: AppBar(
          // LTv Juancho: todos los iconos van a la derecha, estilo cristal.
          automaticallyImplyLeading: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 36, top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Clima (si esta activado)
                  Consumer<WeatherService>(
                    builder: (context, weatherService, _) {
                      return Selector<SettingsService, bool>(
                        selector: (_, settings) => settings.showWeatherInStatusBar,
                        builder: (context, showWeather, _) {
                          if (showWeather && weatherService.hasWeather) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WeatherStatusBarWidget(focusNode: _weatherFocusNode),
                                const SizedBox(width: 14),
                              ],
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                  ),
                  // Uso de datos (si esta activado)
                  Selector<SettingsService, bool>(
                    selector: (_, settings) => settings.showDataWidgetInStatusBar,
                    builder: (context, showData, _) => showData
                      ? Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: _GlassPill(child: const DailyDataUsageWidget()),
                        )
                      : const SizedBox.shrink(),
                  ),
                  // Wi-Fi / red
                  Selector<SettingsService, bool>(
                    selector: (_, settings) => settings.showNetworkIndicatorInStatusBar,
                    builder: (context, showNetwork, _) => showNetwork
                      ? Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: _GlassPill(child: const NetworkWidget()),
                        )
                      : const SizedBox.shrink(),
                  ),
                  // HDMI / entradas
                  Selector<SettingsService, bool>(
                    selector: (_, settings) => settings.showInputsWidgetInStatusBar,
                    builder: (context, showInputs, _) => showInputs
                      ? Consumer<TvInputsService>(
                          builder: (context, tvInputsService, _) {
                            if (tvInputsService.hasInputs) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: _FocusableIconButton(
                                  icon: Icons.settings_input_hdmi_rounded,
                                  focusNode: _inputsFocusNode,
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => const InputsPanel(),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        )
                      : const SizedBox.shrink(),
                  ),
                  // Notificaciones
                  Selector<SettingsService, (bool, bool)>(
                    selector: (_, settings) => (
                      settings.showNotificationsWidgetInStatusBar,
                      settings.autoHideNotificationsWidget
                    ),
                    builder: (context, settingsState, _) {
                      final (showNotifications, autoHide) = settingsState;
                      return showNotifications
                        ? Consumer<NotificationsService>(
                            builder: (context, notificationsService, _) {
                              if (notificationsService.hasPermission) {
                                final count = notificationsService.notifications.length;
                                if (autoHide && count == 0) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: _FocusableIconButton(
                                    icon: count > 0 ? Icons.notifications_active_outlined : Icons.notifications_outlined,
                                    focusNode: _notificationsFocusNode,
                                    badgeCount: count,
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => const NotificationsPanel(),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          )
                        : const SizedBox.shrink();
                    },
                  ),
                  // Ajustes (engranaje) al final, en la esquina
                  _FocusableIconButton(
                    icon: Icons.settings_rounded,
                    focusNode: _settingsFocusNode,
                    onPressed: () => showDialog(context: context, builder: (_) => const SettingsPanel()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Capsula de cristal para indicadores que no son botones (Wi-Fi, datos).
class _GlassPill extends StatelessWidget {
  final Widget child;

  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.30),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.16), width: 1),
      ),
      child: child,
    );
  }
}

/// Boton de icono redondo estilo cristal; al enfocarlo crece y brilla.
class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final int badgeCount;

  const _FocusableIconButton({required this.icon, required this.onPressed, this.focusNode, this.badgeCount = 0});

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const Color accent = kJuanchoGlow;
    final Widget icon = Icon(
      widget.icon,
      size: 26,
      color: Colors.white,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
    );
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: InkWell(
          onTap: widget.onPressed,
          canRequestFocus: false,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          customBorder: const CircleBorder(),
          child: AnimatedScale(
            scale: _focused ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _focused ? Colors.white.withOpacity(0.26) : Colors.black.withOpacity(0.30),
                border: Border.all(
                  color: _focused ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.16),
                  width: _focused ? 2.5 : 1,
                ),
                boxShadow: _focused
                  ? [BoxShadow(color: accent.withOpacity(0.5), blurRadius: 22, spreadRadius: 1)]
                  : const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: widget.badgeCount > 0
                ? Badge(
                    label: Text(widget.badgeCount.toString(), style: const TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red,
                    child: icon,
                  )
                : icon,
            ),
          ),
        ),
      ),
    );
  }
}
