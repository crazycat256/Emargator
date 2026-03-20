import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'desktop_prefs_service.dart';

class DesktopService {
  static const String _trayIconAsset = 'assets/icon-desktop.png';
  static const String _packageName = 'fr.crazycat256.emargator';
  static final DesktopWindowListener _listener = DesktopWindowListener();
  static bool _windowReady = false;
  static bool _pendingBringToFront = false;

  static bool get isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<void> init() async {
    if (!isDesktopPlatform) return;

    await _setupLaunchAtStartup();

    await windowManager.ensureInitialized();
    final keepRunningInBackgroundOnClose =
        await DesktopPrefsService.getKeepRunningInBackgroundOnClose();
    await windowManager.setPreventClose(keepRunningInBackgroundOnClose);

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
      _windowReady = true;

      if (_pendingBringToFront) {
        _pendingBringToFront = false;
        await bringToFront();
      }
    });

    await _initTray();
  }

  static Future<void> _setupLaunchAtStartup() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
        packageName: _packageName,
      );
    } catch (_) {}
  }

  static Future<bool> getLaunchAtStartupEnabled() async {
    if (!isDesktopPlatform) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }

  static Future<void> setLaunchAtStartupEnabled(bool enabled) async {
    if (!isDesktopPlatform) return;
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  static Future<bool> getKeepRunningInBackgroundOnClose() {
    return DesktopPrefsService.getKeepRunningInBackgroundOnClose();
  }

  static Future<void> setKeepRunningInBackgroundOnClose(bool enabled) async {
    await DesktopPrefsService.setKeepRunningInBackgroundOnClose(enabled);
    if (isDesktopPlatform) {
      await windowManager.setPreventClose(enabled);
    }
  }

  static Future<void> bringToFront() async {
    if (!isDesktopPlatform) return;

    if (!_windowReady) {
      _pendingBringToFront = true;
      return;
    }

    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }

    await windowManager.show();
    await windowManager.focus();
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
