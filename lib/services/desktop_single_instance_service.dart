import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'desktop_service.dart';

class DesktopSingleInstanceService {
  static const int _ipcPort = 49213;
  static const String _focusCommand = 'focus-main-window';
  static ServerSocket? _server;

  static Future<bool> ensurePrimaryInstance() async {
    if (!DesktopService.isDesktopPlatform) return true;

    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _ipcPort,
        shared: false,
      );
      _server!.listen(_handleIncomingConnection);
      return true;
    } on SocketException {
      await _signalPrimaryInstance();
      return false;
    }
  }

  static void _handleIncomingConnection(Socket socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((message) {
          if (message.trim() == _focusCommand) {
            unawaited(DesktopService.bringToFront());
          }
        })
        .onDone(() {
          socket.destroy();
        });
  }

  static Future<void> _signalPrimaryInstance() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _ipcPort,
        timeout: const Duration(milliseconds: 600),
      );
      socket.write('$_focusCommand\n');
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }
}
