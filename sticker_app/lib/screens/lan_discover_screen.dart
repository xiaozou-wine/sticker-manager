import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/lan/lan_models.dart';
import '../services/lan/lan_discovery_service.dart';
import '../services/lan/lan_transfer_service.dart';
import '../services/storage_service.dart';
import '../widgets/receive_request_dialog.dart';

class LanDiscoverScreen extends StatefulWidget {
  const LanDiscoverScreen({super.key});

  @override
  State<LanDiscoverScreen> createState() => _LanDiscoverScreenState();
}

class _LanDiscoverScreenState extends State<LanDiscoverScreen> with SingleTickerProviderStateMixin {
  LanDiscoveryService? _discovery;
  LanTransferService? _transfer;
  bool _isSending = false;
  double _sendProgress = 0;
  String _localIp = '获取中...';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final storage = context.read<StorageService>();
    final fp = const Uuid().v4();
    final alias = Platform.isWindows ? 'Windows PC' : 'Android';

    // 获取本机局域网 IP
    _loadLocalIp();

    _discovery = LanDiscoveryService(
      fingerprint: fp,
      alias: alias,
      deviceModel: Platform.operatingSystemVersion,
      deviceType: Platform.isWindows ? 'desktop' : 'mobile',
    );
    _discovery!.addListener(() {
      if (mounted) setState(() {});
    });

    _transfer = LanTransferService(
      storageService: storage,
      senderAlias: alias,
      senderFingerprint: fp,
      onRequestReceived: (request) async {
        if (!mounted) return false;
        return ReceiveRequestDialog.show(context, request);
      },
      onTransferComplete: (packName, count) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已接收「$packName」，$count 个表情')),
        );
      },
    );

    await _discovery!.start();
    try {
      await _transfer!.start();
    } catch (e) {
      debugPrint('[LAN] Transfer service start failed: $e');
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _discovery?.stop();
    _transfer?.stop();
    super.dispose();
  }

  /// 获取本机局域网非回环 IPv4 地址
  Future<void> _loadLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
      if (mounted) setState(() => _localIp = '未找到');
    } catch (e) {
      if (mounted) setState(() => _localIp = '获取失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网发现'),
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildDeviceInfo(),
          Expanded(child: _buildDeviceList()),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final isOnline = _discovery?.isRunning == true;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.blue.shade200, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
          child: Icon(Platform.isWindows ? Icons.computer : Icons.phone_android, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_discovery?.alias ?? '初始化中...',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              Text('$_localIp', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isOnline ? 0.25 : 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8,
              decoration: BoxDecoration(
                color: isOnline ? Colors.greenAccent : Colors.grey,
                shape: BoxShape.circle,
              )),
            const SizedBox(width: 6),
            Text(isOnline ? '在线' : '离线',
                style: TextStyle(fontSize: 12, color: isOnline ? Colors.white : Colors.white70)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDeviceList() {
    final devices = _discovery?.devices ?? [];
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _pulseController.drive(Tween(begin: 0.4, end: 1.0)),
              child: Icon(Icons.wifi_find, size: 80, color: Colors.blue.shade200),
            ),
            const SizedBox(height: 20),
            Text('正在搜索附近设备...', style: TextStyle(color: Colors.grey[600], fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('本机 IP: $_localIp', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            const SizedBox(height: 6),
            Text('确保对方也打开了应用', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isSending ? null : _showManualConnect,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('手动连接'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_isSending) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 0,
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('发送中... ${(_sendProgress * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.w500))),
                  ]),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _sendProgress > 0 ? _sendProgress : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ]),
              ),
            ),
          ),
        ],
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(
                      device.deviceType == 'desktop' ? Icons.computer : Icons.phone_android,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  title: Text(device.alias, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${device.deviceModel}  •  ${device.ip}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  trailing: IconButton(
                    icon: Icon(Icons.arrow_forward_rounded, color: Colors.blue.shade400),
                    onPressed: _isSending ? null : () => _selectPackAndSend(device),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            onPressed: _isSending ? null : _showManualConnect,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('手动连接', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // 手动输入 IP 连接其他设备
  void _showManualConnect() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool testing = false;
        String? errorText;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('手动连接'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: '对方 IP 地址',
                      hintText: '192.168.1.x',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                if (testing)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  FilledButton(
                    onPressed: () async {
                      final ip = ipController.text.trim();
                      if (ip.isEmpty) return;
                      setDialogState(() { testing = true; errorText = null; });
                      try {
                        final ok = await LanTransferService.pingDevice(ip);
                        if (ok) {
                          Navigator.pop(ctx);
                          _selectPackAndSend(LanDevice(
                            fingerprint: 'manual',
                            alias: '手动连接',
                            deviceModel: '',
                            deviceType: 'unknown',
                            port: 53319,
                            ip: ip,
                          ));
                        } else {
                          setDialogState(() { errorText = '无法连接到该设备'; });
                        }
                      } catch (e) {
                        setDialogState(() { errorText = '无法连接到该设备'; });
                      } finally {
                        setDialogState(() { testing = false; });
                      }
                    },
                    child: const Text('连接'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // 选择表情包并发送给目标设备
  Future<void> _selectPackAndSend(LanDevice device) async {
    final storage = context.read<StorageService>();
    final packs = await storage.getAllPacks();
    if (!mounted || packs.isEmpty) return;

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要发送的表情包'),
        children: packs.map((pack) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, pack),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(pack.name),
            subtitle: Text('${pack.stickerCount} 个表情'),
          ),
        )).toList(),
      ),
    );

    if (selected == null || !mounted) return;

    setState(() { _isSending = true; _sendProgress = 0; });

    try {
      final result = await _transfer!.sendPack(
        device: device,
        pack: selected,
        onProgress: (p) {
          if (mounted) setState(() => _sendProgress = p);
        },
      );

      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送成功，${result.receivedCount} 个表情')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发送被拒绝或失败')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _isSending = false; });
    }
  }
}
