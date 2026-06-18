import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'lan_models.dart';

/// 局域网设备发现服务
/// 参考 LocalSend：组播发现 + 单播回复（绕过热点组播限制）
class LanDiscoveryService extends ChangeNotifier {
  static const String _multicastGroup = '224.0.0.167';
  static const int _port = 53317;
  static const Duration _broadcastInterval = Duration(seconds: 3);

  final String fingerprint;
  final String alias;
  final String deviceModel;
  final String deviceType;
  int transferPort;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;
  bool _cleanupPaused = false;
  final Map<String, LanDevice> _devices = {};
  int broadcastCount = 0;
  int receiveCount = 0;
  String lastError = '';
  final List<String> logs = [];

  void _log(String msg) {
    // final ts = DateTime.now().toString().substring(11, 19);
    // logs.add('[$ts] $msg');
    // if (logs.length > 100) logs.removeAt(0);
    // debugPrint('[LAN] $msg');
    // notifyListeners();
  }

  LanDiscoveryService({
    required this.fingerprint,
    required this.alias,
    required this.deviceModel,
    required this.deviceType,
    this.transferPort = 58320,
  });

  List<LanDevice> get devices => _devices.values.toList();
  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      // 绑定到发现端口，用于接收组播和单播回复
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, _port, reuseAddress: true,
      );
      // Windows bug: multicastLoopback=false 会阻止所有组播包
      // 必须设为 true，用 fingerprint 过滤自己的包
      _socket!.multicastLoopback = true;

      // 遍历接口加入组播
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      _log('${interfaces.length} interfaces');
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          try {
            _socket!.joinMulticast(InternetAddress(_multicastGroup), iface);
            _log('+ ${iface.name} (${addr.address})');
          } catch (e) {
            _log('- ${iface.name}: $e');
          }
          break;
        }
      }

      _socket!.listen(_onEvent, onError: (e) {
        _log('Socket error: $e');
        lastError = e.toString();
      });

      // 启动时连续发 3 次 announcement（100ms, 500ms, 2000ms）
      _sendAnnouncementBurst();

      _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _sendMulticast());
      _cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) => _cleanup());

      _log('Listening on UDP $_port');
      _log('Started, fp=${fingerprint.substring(0, 8)}');
    } catch (e) {
      _log('Failed: $e');
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> _sendAnnouncementBurst() async {
    for (final wait in [100, 500, 2000]) {
      await Future.delayed(Duration(milliseconds: wait));
      if (!_isRunning) return;
      _sendMulticast();
    }
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

  void _sendMulticast() {
    if (_socket == null) return;
    final dto = _buildDto();
    final sent = _socket!.send(dto, InternetAddress(_multicastGroup), _port);
    broadcastCount++;
    if (broadcastCount <= 5 || broadcastCount % 10 == 0) {
      _log('TX #$broadcastCount ($sent B)');
    }
  }

  /// 单播回复到指定 IP:port（热点场景下绕过组播限制）
  void _sendUnicast(String targetIp, int targetPort) {
    if (_socket == null) return;
    final dto = _buildDto();
    try {
      _socket!.send(dto, InternetAddress(targetIp), targetPort);
    } catch (_) {}
  }

  List<int> _buildDto() {
    return utf8.encode(jsonEncode({
      'alias': alias, 'deviceModel': deviceModel, 'deviceType': deviceType,
      'fingerprint': fingerprint, 'port': transferPort,
      'appName': 'StickerApp', 'version': '1.0',
    }));
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;
    receiveCount++;
    final fromIp = datagram.address.address;
    final fromPort = datagram.port;

    try {
      final json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (json['appName'] != 'StickerApp') return;
      final fp = json['fingerprint'] as String?;
      if (fp == null) return;

      // 收到自己的包 → 忽略（不要回复，否则无限循环）
      if (fp == fingerprint) return;

      _log('FOUND: ${json['alias']} ($fromIp)');
      final isNew = !_devices.containsKey(fp);
      // 按 IP 去重：移除同 IP 但不同 fingerprint 的旧设备
      _devices.removeWhere((key, d) => d.ip == fromIp && key != fp);
      final existing = _devices[fp];
      if (existing != null) {
        existing.lastSeen = DateTime.now();
      } else {
        _devices[fp] = LanDevice.fromJson(json, fromIp);
        notifyListeners();
      }
      // 只在首次发现时单播回复
      if (isNew) _sendUnicast(fromIp, _port);
    } catch (e) {
      lastError = e.toString();
      _log('Parse error: $e');
    }
  }

  /// 发送期间暂停清理，防止设备列表被过期移除
  void pauseCleanup() => _cleanupPaused = true;
  void resumeCleanup() => _cleanupPaused = false;

  /// 立即发送一次公告，用于发送完成后刷新设备列表
  void sendAnnouncement() => _sendMulticast();

  void _cleanup() {
    if (_cleanupPaused) return;
    final before = _devices.length;
    _devices.removeWhere((_, d) => d.isExpired);
    if (_devices.length != before) notifyListeners();
  }
}
