import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void initDesktopDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<void> initDesktopServices() async {
  await _initWindow();
  await _initHotkey();
  await _initTray();
}

Future<void> disposeDesktopServices() async {
  await hotKeyManager.unregisterAll();
  await trayManager.destroy();
}

Future<void> _initWindow() async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1000, 700),
    minimumSize: Size(600, 400),
    center: true,
    title: 'Sticker Manager',
  );
  await windowManager.waitUntilReadyToShow(windowOptions);
  await windowManager.show();
  await windowManager.focus();
}

Future<void> _initHotkey() async {
  final hotKey = HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );
  await hotKeyManager.register(
    hotKey,
    keyDownHandler: (hotKey) async {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );
}

Future<void> _initTray() async {
  await trayManager.setIcon(
    Platform.isWindows
        ? 'windows/runner/resources/app_icon.ico'
        : 'assets/tray_icon.png',
  );
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: '显示/隐藏'),
        MenuItem(key: 'quit', label: '退出'),
        MenuItem.separator(),
      ],
    ),
  );
  trayManager.addListener(_TrayListener());
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } else if (menuItem.key == 'quit') {
      await disposeDesktopServices();
      exit(0);
    }
  }
}
