import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/lan/lan_models.dart';
import '../services/lan/lan_discovery_service.dart';
import '../services/lan/lan_transfer_service.dart';
import '../services/storage_service.dart';
import '../widgets/receive_request_dialog.dart';
import '../utils/firewall_helper.dart';

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
  bool _transferStarted = false;
  String _transferError = '';
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
    const alias = 'Windows PC';

    // 获取本机局域网 IP
    _loadLocalIp();

    _discovery = LanDiscoveryService(
      fingerprint: fp,
      alias: alias,
      deviceModel: Platform.operatingSystemVersion,
      deviceType: 'desktop',
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
      _transferStarted = true;
      // 广播实际绑定的端口（可能是备用端口）
      _discovery?.transferPort = _transfer!.port;
    } catch (e) {
      debugPrint('[LAN] Transfer service start failed: $e');
      _transferStarted = false;
      _transferError = e.toString();
    }
    if (mounted) setState(() {});

    if (_transferStarted && mounted) {
      // 传输服务启动成功，检查防火墙入站规则
      final fwResult = await FirewallHelper.ensureRule();
      if (!fwResult.ok && mounted) {
        _showFirewallDialog();
      }
    } else if (!_transferStarted && mounted) {
      // 传输服务启动失败，提示排查步骤
      _showTransferFailedDialog();
    }
  }

  /// 传输服务启动失败时，弹窗提示排查步骤
  void _showTransferFailedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('传输服务启动失败'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('错误: $_transferError',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              // 原因 1：端口被占用
              const Text('① 端口被占用（最常见）', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('按 Win 键搜索"PowerShell"，打开后执行：'),
              const SizedBox(height: 4),
              _buildCopyableCommand('netstat -ano | findstr 28320'),
              const SizedBox(height: 4),
              const Text('如果看到 LISTENING 行，记下最后的 PID 数字，然后执行：'),
              const SizedBox(height: 4),
              _buildCopyableCommand('taskkill /PID <PID数字> /F'),
              const SizedBox(height: 4),
              const Text('或直接关闭所有 Sticker Manager 窗口后重试。'),
              const SizedBox(height: 16),
              // 原因 2：防火墙
              const Text('② 防火墙阻止入站连接', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('右键开始菜单 → Windows PowerShell(管理员)，执行：'),
              const SizedBox(height: 4),
              _buildCopyableCommand(
                'netsh advfirewall firewall add rule name="Sticker Manager LAN Transfer" dir=in action=allow protocol=TCP localport=53320',
              ),
              const SizedBox(height: 16),
              // 原因 3：权限
              const Text('③ 权限不足', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('右键应用图标 → 以管理员身份运行'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _retryTransfer();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建可复制的命令行块
  Widget _buildCopyableCommand(String command) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(children: [
        Expanded(
          child: SelectableText(command, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: command));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
            );
          },
          child: Tooltip(
            message: '复制',
            child: Icon(Icons.copy, size: 16, color: Colors.grey.shade600),
          ),
        ),
      ]),
    );
  }

  /// 重试启动传输服务
  Future<void> _retryTransfer() async {
    try {
      await _transfer!.start();
      _transferStarted = true;
      _transferError = '';
    } catch (e) {
      _transferStarted = false;
      _transferError = e.toString();
    }
    if (mounted) setState(() {});

    if (_transferStarted && mounted) {
      final fwResult = await FirewallHelper.ensureRule();
      if (!fwResult.ok && mounted) {
        _showFirewallDialog();
      }
    } else if (!_transferStarted && mounted) {
      _showTransferFailedDialog();
    }
  }

  /// 防火墙规则添加失败时，弹窗提示用户手动操作
  void _showFirewallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要允许防火墙入站'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('局域网互传需要 TCP 53320 端口的入站权限，否则对方无法发送文件给你。'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  FirewallHelper.manualInstructions,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
        title: const Text('局域网传输'),
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
    final transferOk = _transferStarted;
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
          child: const Icon(Icons.computer, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_discovery?.alias ?? '初始化中...',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              Text(_localIp, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8))),
              if (!transferOk && isOnline) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _showTransferFailedDialog,
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: Colors.yellow.shade200),
                    const SizedBox(width: 4),
                    Expanded(child: Text('传输服务未启动，点击查看解决方法',
                      style: TextStyle(fontSize: 11, color: Colors.yellow.shade200,
                        decoration: TextDecoration.underline))),
                  ]),
                ),
              ],
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
            if (transferOk) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('可传输', style: TextStyle(fontSize: 12, color: Colors.white)),
                ]),
              ),
            ],
          ],
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

  // 选择多个表情包并依次发送给目标设备
  Future<void> _selectPackAndSend(LanDevice device) async {
    final storage = context.read<StorageService>();
    final packs = await storage.getAllPacks();
    if (!mounted || packs.isEmpty) return;

    final selected = await showDialog<List<dynamic>>(
      context: context,
      builder: (ctx) => _MultiPackSelectDialog(packs: packs),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() { _isSending = true; _sendProgress = 0; });
    // 暂停设备清理，防止长时间上传导致设备过期消失
    _discovery?.pauseCleanup();

    int totalSent = 0;
    int failedPacks = 0;
    try {
      for (int i = 0; i < selected.length; i++) {
        if (!mounted) break;
        final pack = selected[i];
        setState(() => _sendProgress = i / selected.length);
        try {
          final result = await _transfer!.sendPack(
            device: device,
            pack: pack,
            onProgress: (p) {
              if (mounted) setState(() => _sendProgress = (i + p) / selected.length);
            },
          );
          if (result.success) {
            totalSent += result.receivedCount;
          } else {
            failedPacks++;
          }
        } catch (e) {
          failedPacks++;
          debugPrint('[LAN] Send pack "${pack.name}" failed: $e');
        }
      }

      if (!mounted) return;
      if (failedPacks == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送完成，共 $totalSent 个表情')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送完成，$totalSent 个成功，$failedPacks 个包失败')),
        );
      }
    } finally {
      _discovery?.resumeCleanup();
      _discovery?.sendAnnouncement();
      if (mounted) setState(() { _isSending = false; });
    }
  }
}

/// 多选表情包弹窗
class _MultiPackSelectDialog extends StatefulWidget {
  final List<dynamic> packs;
  const _MultiPackSelectDialog({required this.packs});

  @override
  State<_MultiPackSelectDialog> createState() => _MultiPackSelectDialogState();
}

class _MultiPackSelectDialogState extends State<_MultiPackSelectDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要发送的表情包'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.packs.length,
          itemBuilder: (ctx, i) {
            final pack = widget.packs[i];
            return CheckboxListTile(
              value: _selected.contains(i),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selected.add(i);
                  } else {
                    _selected.remove(i);
                  }
                });
              },
              title: Text(pack.name),
              subtitle: Text('${pack.stickerCount} 个表情'),
              controlAffinity: ListTileControlAffinity.leading,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.map((i) => widget.packs[i]).toList()),
          child: Text('发送 (${_selected.length})'),
        ),
      ],
    );
  }
}
