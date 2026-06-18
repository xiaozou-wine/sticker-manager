# LAN Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement LocalSend-style LAN sticker pack transfer for Android and Windows PC Flutter apps
**Architecture:** UDP multicast discovery (239.0.0.170:53319) + HTTP REST file transfer (port 53319), pure Dart
**Tech Stack:** dart:io (RawDatagramSocket, HttpServer), dio (existing), uuid (existing), Provider (existing)

---

## Task 1: Data Models

**Files:**
- Create: `sticker_app/lib/services/lan/lan_models.dart`

- [ ] **Step 1: Create lan_models.dart**

```dart
class LanDevice {
  final String fingerprint;
  final String alias;
  final String deviceModel;
  final String deviceType;
  final int port;
  final String ip;
  DateTime lastSeen;

  LanDevice({
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    required this.port,
    required this.ip,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(lastSeen).inSeconds > 15;

  factory LanDevice.fromJson(Map<String, dynamic> json, String ip) {
    return LanDevice(
      fingerprint: json['fingerprint'] as String,
      alias: json['alias'] as String? ?? 'Unknown',
      deviceModel: json['deviceModel'] as String? ?? '',
      deviceType: json['deviceType'] as String? ?? 'mobile',
      port: json['port'] as int? ?? 53319,
      ip: ip,
    );
  }

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'deviceModel': deviceModel,
    'deviceType': deviceType,
    'fingerprint': fingerprint,
    'port': port,
    'appName': 'StickerApp',
    'version': '1.0',
  };
}

class LanTransferRequest {
  final String packName;
  final String packId;
  final int stickerCount;
  final int totalSizeBytes;
  final String senderName;
  final String senderFingerprint;

  LanTransferRequest({
    required this.packName,
    required this.packId,
    required this.stickerCount,
    required this.totalSizeBytes,
    required this.senderName,
    required this.senderFingerprint,
  });

  factory LanTransferRequest.fromJson(Map<String, dynamic> json) {
    return LanTransferRequest(
      packName: json['packName'] as String,
      packId: json['packId'] as String,
      stickerCount: json['stickerCount'] as int,
      totalSizeBytes: json['totalSizeBytes'] as int? ?? 0,
      senderName: json['senderName'] as String? ?? 'Unknown',
      senderFingerprint: json['senderFingerprint'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'packName': packName,
    'packId': packId,
    'stickerCount': stickerCount,
    'totalSizeBytes': totalSizeBytes,
    'senderName': senderName,
    'senderFingerprint': senderFingerprint,
  };
}

class LanTransferResult {
  final bool success;
  final int receivedCount;
  final int failedCount;

  LanTransferResult({
    required this.success,
    required this.receivedCount,
    required this.failedCount,
  });

  factory LanTransferResult.fromJson(Map<String, dynamic> json) {
    return LanTransferResult(
      success: json['success'] as bool? ?? false,
      receivedCount: json['receivedCount'] as int? ?? 0,
      failedCount: json['failedCount'] as int? ?? 0,
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd sticker_app && flutter analyze lib/services/lan/lan_models.dart`

- [ ] **Step 3: Commit**

```bash
git add sticker_app/lib/services/lan/lan_models.dart
git commit -m "feat(lan): add data models for LAN transfer"
```

---

## Task 2: Discovery Service

**Files:**
- Create: `sticker_app/lib/services/lan/lan_discovery_service.dart`

- [ ] **Step 1: Create lan_discovery_service.dart**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'lan_models.dart';

class LanDiscoveryService extends ChangeNotifier {
  static const String _multicastGroup = '239.0.0.170';
  static const int _port = 53319;
  static const Duration _broadcastInterval = Duration(seconds: 3);

  final String fingerprint;
  final String alias;
  final String deviceModel;
  final String deviceType;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;
  final Map<String, LanDevice> _devices = {};

  LanDiscoveryService({
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
  });

  List<LanDevice> get devices => _devices.values.toList();
  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4, _port, reuseAddress: true,
    );
    _socket!.multicastLoopback = false;
    _socket!.joinMulticast(InternetAddress(_multicastGroup));
    _socket!.listen(_onData);
    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _broadcast());
    _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) => _cleanup());
    _broadcast();
  }

  void stop() {
    _isRunning = false;
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _socket = null;
    _devices.clear();
    notifyListeners();
  }

  void _broadcast() {
    if (_socket == null) return;
    final message = jsonEncode({
      'alias': alias, 'deviceModel': deviceModel, 'deviceType': deviceType,
      'fingerprint': fingerprint, 'port': _port, 'appName': 'StickerApp', 'version': '1.0',
    });
    _socket!.send(utf8.encode(message), InternetAddress(_multicastGroup), _port);
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;
    try {
      final json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (json['appName'] != 'StickerApp') return;
      final fp = json['fingerprint'] as String?;
      if (fp == null || fp == fingerprint) return;
      final ip = datagram.address.address;
      final existing = _devices[fp];
      if (existing != null) {
        existing.lastSeen = DateTime.now();
      } else {
        _devices[fp] = LanDevice.fromJson(json, ip);
        notifyListeners();
      }
    } catch (_) {}
  }

  void _cleanup() {
    final before = _devices.length;
    _devices.removeWhere((_, d) => d.isExpired);
    if (_devices.length != before) notifyListeners();
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd sticker_app && flutter analyze lib/services/lan/lan_discovery_service.dart`

- [ ] **Step 3: Commit**

```bash
git add sticker_app/lib/services/lan/lan_discovery_service.dart
git commit -m "feat(lan): add UDP multicast discovery service"
```

---

## Task 3: Transfer Service

**Files:**
- Create: `sticker_app/lib/services/lan/lan_transfer_service.dart`
- Modify: `sticker_app/lib/models/sticker_pack.dart` (add toJson)

- [ ] **Step 1: Add toJson() to StickerPack**

In `sticker_app/lib/models/sticker_pack.dart`, add this method to the StickerPack class:

```dart
Map<String, dynamic> toJson() => {
  'id': id, 'name': name, 'description': description, 'stickerCount': stickerCount,
};
```

- [ ] **Step 2: Create lan_transfer_service.dart**

See full source in design spec. Key components:
- `HttpServer` on port 53319 (dart:io)
- `POST /api/sticker/send` — accept/decline with callback
- `POST /api/sticker/upload` — multipart parser, saves to StorageService
- `GET /api/sticker/ping` — health check
- `sendPack()` — sends pack to remote device via dio (2-step: request then upload)

- [ ] **Step 3: Verify compilation**

Run: `cd sticker_app && flutter analyze lib/services/lan/`

- [ ] **Step 4: Commit**

```bash
git add sticker_app/lib/services/lan/lan_transfer_service.dart sticker_app/lib/models/sticker_pack.dart
git commit -m "feat(lan): add HTTP transfer service for LAN file transfer"
```

---

## Task 4: Receive Request Dialog

**Files:**
- Create: `sticker_app/lib/widgets/receive_request_dialog.dart`

- [ ] **Step 1: Create the dialog widget**

```dart
import 'package:flutter/material.dart';
import '../services/lan/lan_models.dart';

class ReceiveRequestDialog extends StatelessWidget {
  final LanTransferRequest request;
  const ReceiveRequestDialog({super.key, required this.request});

  static Future<bool> show(BuildContext context, LanTransferRequest request) async {
    final result = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => ReceiveRequestDialog(request: request),
    );
    return result ?? false;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('收到传输请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${request.senderName} 想发送给你:'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.folder_zip, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.packName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${request.stickerCount} 个表情',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              )),
            ]),
          ),
          if (request.totalSizeBytes > 0) ...[
            const SizedBox(height: 8),
            Text('大小: ${_formatSize(request.totalSizeBytes)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('拒绝')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('接受')),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd sticker_app && flutter analyze lib/widgets/receive_request_dialog.dart`

- [ ] **Step 3: Commit**

```bash
git add sticker_app/lib/widgets/receive_request_dialog.dart
git commit -m "feat(lan): add receive request dialog widget"
```

---

## Task 5: LAN Discover Screen (Android)

**Files:**
- Create: `sticker_app/lib/screens/lan_discover_screen.dart`

- [ ] **Step 1: Create the LAN discover screen**

Key UI:
- Top: device info card (alias, online status, send progress)
- Middle: device list (icon + name + model + IP, tap to send)
- Empty state: "正在搜索附近设备..."
- Select pack dialog: list all packs, tap to send

Full source includes:
- `LanDiscoveryService` + `LanTransferService` lifecycle
- `_selectPackAndSend()` — shows pack picker dialog, then calls `transfer.sendPack()`
- `_buildDeviceInfo()` — shows alias, online badge, progress bar
- `_buildDeviceList()` — ListView of discovered devices

- [ ] **Step 2: Verify compilation**

Run: `cd sticker_app && flutter analyze lib/screens/lan_discover_screen.dart`

- [ ] **Step 3: Commit**

```bash
git add sticker_app/lib/screens/lan_discover_screen.dart
git commit -m "feat(lan): add LAN discover screen for Android"
```

---

## Task 6: Android Integration

**Files:**
- Modify: `sticker_app/lib/screens/home_screen.dart`
- Modify: `sticker_app/lib/main.dart`

- [ ] **Step 1: Add LAN entry to home screen**

In `sticker_app/lib/screens/home_screen.dart`:

Add import:
```dart
import 'lan_discover_screen.dart';
```

Add IconButton in AppBar actions (before `_buildSortButton()`):
```dart
IconButton(
  icon: const Icon(Icons.wifi_find),
  tooltip: '局域网传输',
  onPressed: () => Navigator.push(
    context, MaterialPageRoute(builder: (_) => const LanDiscoverScreen()),
  ),
),
```

Add list tile in `_showAddOptions` bottom sheet:
```dart
ListTile(
  leading: const Icon(Icons.wifi_find),
  title: const Text('局域网传输'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LanDiscoverScreen()));
  },
),
```

- [ ] **Step 2: Handle sticker://lan/ deep links**

In `sticker_app/lib/main.dart`, add import:
```dart
import 'screens/lan_discover_screen.dart';
```

Update `_handleLink` to handle `sticker://lan/` links by navigating to LanDiscoverScreen.

- [ ] **Step 3: Verify app builds**

Run: `cd sticker_app && flutter build apk --debug`

- [ ] **Step 4: Commit**

```bash
git add sticker_app/lib/screens/home_screen.dart sticker_app/lib/main.dart
git commit -m "feat(lan): integrate LAN discover into Android home screen"
```

---

## Task 7: LAN Service Files for PC

**Files:**
- Copy: LAN service files from sticker_app to sticker_pc

- [ ] **Step 1: Create directories and copy files**

```bash
mkdir -p sticker_pc/lib/services/lan
mkdir -p sticker_pc/lib/widgets
```

Copy (identical content):
- `sticker_app/lib/services/lan/lan_models.dart` -> `sticker_pc/lib/services/lan/lan_models.dart`
- `sticker_app/lib/services/lan/lan_discovery_service.dart` -> `sticker_pc/lib/services/lan/lan_discovery_service.dart`
- `sticker_app/lib/services/lan/lan_transfer_service.dart` -> `sticker_pc/lib/services/lan/lan_transfer_service.dart`
- `sticker_app/lib/widgets/receive_request_dialog.dart` -> `sticker_pc/lib/widgets/receive_request_dialog.dart`

- [ ] **Step 2: Verify PC project compiles**

Run: `cd sticker_pc && flutter analyze lib/services/lan/`

- [ ] **Step 3: Commit**

```bash
git add sticker_pc/lib/services/lan/ sticker_pc/lib/widgets/receive_request_dialog.dart
git commit -m "feat(lan): add LAN transfer services to PC project"
```

---

## Task 8: LAN Discover Screen (PC) + Integration

**Files:**
- Create: `sticker_pc/lib/screens/lan_discover_screen.dart`
- Modify: `sticker_pc/lib/screens/home_screen.dart`
- Modify: `sticker_pc/lib/main.dart`

- [ ] **Step 1: Create PC-specific LAN discover screen**

Nearly identical to Android version but with desktop icons (Icons.computer) and simplified pack picker.

- [ ] **Step 2: Add LAN entry to PC home screen**

In `sticker_pc/lib/screens/home_screen.dart`:

Add import:
```dart
import 'lan_discover_screen.dart';
```

Add IconButton in AppBar actions:
```dart
IconButton(
  icon: const Icon(Icons.wifi_find),
  tooltip: '局域网传输',
  onPressed: () => Navigator.push(
    context, MaterialPageRoute(builder: (_) => const LanDiscoverScreen()),
  ),
),
```

Add to `_showAddOptions` bottom sheet:
```dart
ListTile(
  leading: const Icon(Icons.wifi_find),
  title: const Text('局域网传输'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LanDiscoverScreen()));
  },
),
```

- [ ] **Step 3: Handle sticker://lan/ deep links**

In `sticker_pc/lib/main.dart`, add import and update `_handleLink` for `sticker://lan/` links.

- [ ] **Step 4: Verify PC builds**

Run: `cd sticker_pc && flutter build windows --debug`

- [ ] **Step 5: Commit**

```bash
git add sticker_pc/lib/screens/lan_discover_screen.dart sticker_pc/lib/screens/home_screen.dart sticker_pc/lib/main.dart
git commit -m "feat(lan): integrate LAN discover into PC home screen"
```

---

## Summary

| Task | Files | Description |
|------|-------|-------------|
| 1 | lan_models.dart | Data models (LanDevice, LanTransferRequest, LanTransferResult) |
| 2 | lan_discovery_service.dart | UDP multicast discovery (239.0.0.170:53319) |
| 3 | lan_transfer_service.dart + sticker_pack.dart | HTTP transfer server + sendPack() |
| 4 | receive_request_dialog.dart | Accept/decline dialog |
| 5 | lan_discover_screen.dart (Android) | Discover page UI |
| 6 | home_screen.dart + main.dart (Android) | Android integration |
| 7 | Copy lan files to sticker_pc | PC service files |
| 8 | lan_discover_screen.dart + home + main (PC) | PC UI + integration |
