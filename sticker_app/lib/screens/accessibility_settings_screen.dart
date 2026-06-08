import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';
import 'ui_snapshot_screen.dart';

/// Settings page for configuring the accessibility service integration.
/// Lets users check status, open system settings, and test the overlay.
class AccessibilitySettingsScreen extends StatefulWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  State<AccessibilitySettingsScreen> createState() => _AccessibilitySettingsScreenState();
}

class _AccessibilitySettingsScreenState extends State<AccessibilitySettingsScreen> with WidgetsBindingObserver {
  bool _serviceEnabled = false;
  bool _overlayPermission = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh status when returning from system settings
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    final service = await AccessibilityService.isServiceEnabled();
    final overlay = await AccessibilityService.isOverlayPermissionGranted();
    if (mounted) {
      setState(() {
        _serviceEnabled = service;
        _overlayPermission = overlay;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天表情集成'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStatus,
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildSetupSection(),
                const SizedBox(height: 16),
                if (_serviceEnabled) _buildSnapshotButton(),
                if (_serviceEnabled) const SizedBox(height: 16),
                _buildHowItWorks(),
                const SizedBox(height: 16),
                _buildSupportedApps(),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    final allReady = _serviceEnabled && _overlayPermission;
    return Card(
      color: allReady ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              allReady ? Icons.check_circle : Icons.warning_amber,
              size: 48,
              color: allReady ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 8),
            Text(
              allReady ? '已就绪' : '需要配置',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: allReady ? Colors.green[700] : Colors.orange[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              allReady ? '可以在 QQ/微信中使用表情快捷发送' : '请完成以下配置步骤',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('配置步骤', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildStep(
          number: 1,
          title: '开启无障碍服务',
          subtitle: '允许 App 监听 QQ/微信的界面状态',
          done: _serviceEnabled,
          onTap: () async {
            await AccessibilityService.openAccessibilitySettings();
          },
        ),
        _buildStep(
          number: 2,
          title: '忽略电池优化',
          subtitle: '防止系统杀后台，保持服务长期运行',
          done: false,
          onTap: () async {
            await AccessibilityService.requestIgnoreBatteryOptimizations();
          },
        ),
        _buildStep(
          number: 3,
          title: '允许自启动',
          subtitle: '开机后自动启动（小米/华为/OPPO/Vivo）',
          done: false,
          onTap: () async {
            await AccessibilityService.openAutoStartSettings();
          },
        ),
      ],
    );
  }

  Widget _buildSnapshotButton() {
    return Card(
      color: Colors.blue[50],
      child: ListTile(
        leading: Icon(Icons.camera_alt, color: Colors.blue[700]),
        title: const Text('抓取 UI 节点树'),
        subtitle: const Text('打开 QQ/微信聊天窗口后，点击这里查看界面节点'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UISnapshotScreen()),
        ),
      ),
    );
  }

  Widget _buildStep({
    required int number,
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: done ? Colors.green : Colors.grey[300],
          child: done
              ? const Icon(Icons.check, color: Colors.white)
              : Text('$number', style: const TextStyle(color: Colors.black54)),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: done
            ? const Text('已完成', style: TextStyle(color: Colors.green))
            : const Icon(Icons.chevron_right),
        onTap: done ? null : onTap,
      ),
    );
  }

  Widget _buildKeepAliveSection() {
    return Card(
      color: Colors.purple[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('防止服务被杀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.purple[700])),
            const SizedBox(height: 12),
            const Text('国产手机系统会自动清理后台服务，以下设置可以防止无障碍服务被杀：'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.battery_saver),
                label: const Text('关闭电池优化'),
                onPressed: () => AccessibilityService.requestIgnoreBatteryOptimizations(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.start),
                label: const Text('开启自启动'),
                onPressed: () => AccessibilityService.openAutoStartSettings(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('使用方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildStepRow(Icons.download, '在 App 中下载表情包集'),
            _buildStepRow(Icons.photo_library, '表情自动保存到手机相册'),
            _buildStepRow(Icons.chat, '在 QQ/微信聊天中点 "+" → 相册'),
            _buildStepRow(Icons.folder, '找到 StickerApp 文件夹'),
            _buildStepRow(Icons.send, '选择表情直接发送（GIF 保留动画）'),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildSupportedApps() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('支持的应用', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildAppRow('QQ', 'com.tencent.mobileqq', true),
            const Divider(),
            _buildAppRow('微信', 'com.tencent.mm', true),
          ],
        ),
      ),
    );
  }

  Widget _buildAppRow(String name, String package, bool supported) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        supported ? Icons.check_circle : Icons.circle_outlined,
        color: supported ? Colors.green : Colors.grey,
      ),
      title: Text(name),
      subtitle: Text(package, style: const TextStyle(fontSize: 11)),
    );
  }
}
