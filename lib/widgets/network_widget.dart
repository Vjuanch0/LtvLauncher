import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/widgets/juancho_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NetworkWidget extends StatelessWidget
{
  const NetworkWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<NetworkService, (NetworkType, CellularNetworkType, int, bool, String?)>(
      selector: (_, ns) => (ns.networkType, ns.cellularNetworkType, ns.wirelessNetworkSignalLevel, ns.vpnActive, ns.ssid),
      builder: (context, state, _) {
        final (networkType, cellularNetworkType, wirelessSignalLevel, vpnActive, ssid) = state;
        final networkService = context.read<NetworkService>();
        IconData physicalIcon = Icons.link_off;
        Color? iconColor;

        switch (networkType)
        {
          case NetworkType.Cellular:
            switch (cellularNetworkType)
            {
              case CellularNetworkType.Cdma || CellularNetworkType.Gsm || CellularNetworkType.Gprs:
                physicalIcon = Icons.g_mobiledata;

              case CellularNetworkType.Edge: physicalIcon = Icons.e_mobiledata;

              case CellularNetworkType.Hspa || CellularNetworkType.Hsdpa || CellularNetworkType.Hsupa:
                physicalIcon = Icons.h_mobiledata;

              case CellularNetworkType.Hspap: physicalIcon = Icons.h_plus_mobiledata;

              case CellularNetworkType.Umts || CellularNetworkType.TdScdma:
                physicalIcon = Icons.three_g_mobiledata; break;

              case CellularNetworkType.Lte: physicalIcon = Icons.four_g_mobiledata_outlined; break;
              case CellularNetworkType.Nr: physicalIcon = Icons.five_g;

              default: physicalIcon = Icons.question_mark; break;
            }
            break;
          case NetworkType.Wifi:
            if (wirelessSignalLevel == 0) {
              physicalIcon = Icons.signal_wifi_0_bar;
            }
            else if (wirelessSignalLevel == 1) {
              physicalIcon = Icons.network_wifi_1_bar;
            }
            else if (wirelessSignalLevel == 2) {
              physicalIcon = Icons.network_wifi_2_bar;
            }
            else if (wirelessSignalLevel == 3) {
              physicalIcon = Icons.network_wifi_3_bar;
            }
            else {
              physicalIcon = Icons.signal_wifi_4_bar;
            }
            break;
          case NetworkType.Vpn: physicalIcon = Icons.vpn_key; break;
          case NetworkType.Wired: physicalIcon = Icons.lan; break;
          case NetworkType.Unknown: 
            physicalIcon = Icons.link_off;
            iconColor = Colors.red; // Make no connection icon red
            break;
        }

        Widget physicalWidget = Icon(
          physicalIcon,
          size: 30,
          color: iconColor ?? Colors.white,
          shadows: const [
            Shadow(
              color: Colors.black54,
              offset: Offset(0, 2),
              blurRadius: 8
            )
          ]
        );

        // LTv Juancho: nombre de la red debajo del icono.
        final String networkName;
        if (networkType == NetworkType.Wifi) {
          networkName = (ssid != null && ssid.isNotEmpty) ? ssid : 'Wi-Fi';
        } else if (networkType == NetworkType.Wired) {
          networkName = 'Cable';
        } else if (networkType == NetworkType.Vpn) {
          networkName = 'VPN';
        } else if (networkType == NetworkType.Cellular) {
          networkName = 'Móvil';
        } else {
          networkName = 'Sin red';
        }
        physicalWidget = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            physicalWidget,
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                networkName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.85),
                  shadows: const [Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 8)],
                ),
              ),
            ),
          ],
        );

        if (!vpnActive || physicalIcon == Icons.vpn_key) {
          return _NetworkIconButton(
            onTap: () {
              if (vpnActive || networkType == NetworkType.Vpn) {
                networkService.openVpnSettings();
              } else {
                networkService.openWifiSettings();
              }
            },
            child: physicalWidget,
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NetworkIconButton(
              onTap: () => networkService.openWifiSettings(),
              child: physicalWidget,
            ),
            const SizedBox(width: 4),
            _NetworkIconButton(
              onTap: () => networkService.openVpnSettings(),
              child: const Icon(
                Icons.vpn_key,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  )
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NetworkIconButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _NetworkIconButton({
    required this.onTap,
    required this.child,
  });

  @override
  State<_NetworkIconButton> createState() => _NetworkIconButtonState();
}

class _NetworkIconButtonState extends State<_NetworkIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onTap()),
      },
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: InkWell(
          onTap: widget.onTap,
          canRequestFocus: false,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedScale(
            scale: _focused ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.child,
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: _focused ? kJuanchoGlow : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: _focused ? [BoxShadow(color: kJuanchoGlow.withOpacity(0.7), blurRadius: 10)] : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}