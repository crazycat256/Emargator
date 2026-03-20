import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class DesktopService {
  static const String _trayIconAsset = 'assets/icon.png';
  static final DesktopWindowListener _listener = DesktopWindowListener();

  static Future<void> init() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true); // Don't close the app directly

    windowManager.addListener(_listener);
    trayManager.addListener(_listener);

    const windowOptions = WindowOptions(
      size: Size(450, 715),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await _initTray();
  }

  static Future<void> _initTray() async {
    final iconPath = await _resolveTrayIconPath();
    await trayManager.setIcon(iconPath);
    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: 'Afficher Emargator'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Quitter'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  static Future<String> _resolveTrayIconPath() async {
    try {
      final byteData = await rootBundle.load(_trayIconAsset);
      final bytes = byteData.buffer.asUint8List();
      final file = File('${Directory.systemTemp.path}/emargator_tray_icon.png');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return _trayIconAsset;
    }
  }
}

class DesktopWindowListener extends WindowListener with TrayListener {
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
    }
  }
}
