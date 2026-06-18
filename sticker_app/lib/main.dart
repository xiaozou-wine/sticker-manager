import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'services/storage_service.dart';
import 'providers/pack_provider.dart';
import 'providers/sticker_provider.dart';
import 'screens/home_screen.dart';
import 'screens/import_link_screen.dart';
import 'screens/lan_discover_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  runApp(MyApp(storage: storage));
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
    _initShareIntent();
  }

  void _initShareIntent() {
    final intent = ReceiveSharingIntent.instance;
    intent.getInitialMedia().then((files) {
      if (files.isNotEmpty) _handleSharedFiles(files);
    });
    intent.getMediaStream().listen((files) {
      if (files.isNotEmpty) _handleSharedFiles(files);
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    final fileList = files.map((f) => File(f.path)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => HomeScreen(sharedFiles: fileList),
        ),
      );
    });
  }

  void _initDeepLinks() {
    try {
      final appLinks = AppLinks();
      appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleLink(uri.toString());
      }).catchError((e) {
        debugPrint('getInitialLink error: $e');
      });
      appLinks.uriLinkStream.listen((uri) {
        _handleLink(uri.toString());
      }, onError: (e) {
        debugPrint('uriLinkStream error: $e');
      });
    } catch (e) {
      debugPrint('initDeepLinks error: $e');
    }
  }

  void _handleLink(String link) {
    if (link.startsWith('sticker://share/')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ImportLinkScreen(initialLink: link),
          ),
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
