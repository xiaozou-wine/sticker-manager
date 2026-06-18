import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'services/storage_service.dart';
import 'services/settings_service.dart';
import 'services/hotkey_service.dart';
import 'config.dart';
import 'providers/pack_provider.dart';
import 'providers/sticker_provider.dart';
import 'screens/home_screen.dart';
import 'screens/import_link_screen.dart';
import 'screens/lan_discover_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  StorageService.initFfi();
  final storage = StorageService();
  await AppConfig.init();

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

  runApp(MyApp(storage: storage));

  final hotkeyConfig = await SettingsService.loadHotkeyConfig();
  await registerHotkey(hotkeyConfig);
  await _initTray();
}

Future<void> _initTray() async {
  await trayManager.setIcon('assets/images/tray_icon.ico');
  await trayManager.setContextMenu(
    Menu(items: [
      MenuItem(key: 'show', label: '显示/隐藏'),
      MenuItem(key: 'quit', label: '退出'),
      MenuItem.separator(),
    ]),
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
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

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
      await hotKeyManager.unregisterAll();
      await trayManager.destroy();
      exit(0);
    }
  }
}

class MyApp extends StatefulWidget {
  final StorageService storage;
  const MyApp({super.key, required this.storage});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    try {
      final appLinks = AppLinks();
      appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleLink(uri.toString());
      }).catchError((e) => debugPrint('getInitialLink error: $e'));
      appLinks.uriLinkStream.listen(
        (uri) => _handleLink(uri.toString()),
        onError: (e) => debugPrint('uriLinkStream error: $e'),
      );
    } catch (e) {
      debugPrint('initDeepLinks error: $e');
    }
  }

  void _handleLink(String link) {
    if (link.startsWith('sticker://share/')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ImportLinkScreen(initialLink: link)),
        );
      });
    } else if (link.startsWith('sticker://lan/')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const LanDiscoverScreen()),
        );
      });
    }
  }

  @override
  void dispose() {
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: widget.storage),
        ChangeNotifierProvider(create: (_) => PackProvider(widget.storage)),
        ChangeNotifierProvider(create: (_) => StickerProvider(widget.storage)),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Sticker Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
