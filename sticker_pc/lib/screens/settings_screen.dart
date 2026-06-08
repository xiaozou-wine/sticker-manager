import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/hotkey_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  HotkeyConfig? _currentConfig;
  bool _isRecording = false;
  final _serverController = TextEditingController();
  String _savedServerAddr = '';

  // Keys currently held down (for tracking modifier state).
  final Set<PhysicalKeyboardKey> _heldModifiers = {};
  // The non-modifier key captured during recording.
  PhysicalKeyboardKey? _capturedKey;
  // Modifiers that were held when the non-modifier key was pressed.
  final List<String> _capturedModifiers = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await SettingsService.loadHotkeyConfig();
    final serverAddr = await SettingsService.loadApiBaseUrl();
    if (mounted) {
      setState(() {
        _currentConfig = config;
        _savedServerAddr = serverAddr;
        _serverController.text = serverAddr;
      });
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isRecording) return false;

    final key = event.physicalKey;

    if (isModifierKey(key)) {
      if (event is KeyDownEvent) {
        _heldModifiers.add(key);
      } else if (event is KeyUpEvent) {
        _heldModifiers.remove(key);
      }
      // Update display while recording modifiers.
      if (mounted) setState(() {});
      return true;
    }

    // Non-modifier key.
    if (event is KeyDownEvent) {
      _capturedKey = key;
      _capturedModifiers
        ..clear()
        ..addAll(_heldModifiers
            .map(modifierKeyToConfigLabel)
            .where((s) => s != null)
            .cast<String>());
      if (mounted) setState(() {});
      return true;
    } else if (event is KeyUpEvent && _capturedKey == key) {
      // The captured non-modifier key was released -- finalize.
      _finalizeRecording();
      return true;
    }

    return false;
  }

  Future<void> _finalizeRecording() async {
    if (_capturedKey == null) return;

    final keyLabel = physicalKeyToConfigLabel(_capturedKey!);
    if (keyLabel == null) {
      // Unknown key -- stay in recording mode.
      _capturedKey = null;
      _capturedModifiers.clear();
      if (mounted) setState(() {});
      return;
    }

    // Require at least one modifier for a valid hotkey.
    if (_capturedModifiers.isEmpty) {
      // No modifier held -- ignore and stay in recording mode.
      _capturedKey = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('快捷键必须包含至少一个修饰键 (Ctrl/Shift/Alt)')),
        );
        setState(() {});
      }
      return;
    }

    final newConfig = HotkeyConfig(
      keyLabel: keyLabel,
      keyCode: _capturedKey!.usbHidUsage,
      modifiers: List.unmodifiable(_capturedModifiers),
    );

    await SettingsService.saveHotkeyConfig(newConfig);

    _capturedKey = null;
    _capturedModifiers.clear();
    _heldModifiers.clear();

    if (mounted) {
      setState(() {
        _currentConfig = newConfig;
        _isRecording = false;
      });
      Navigator.pop(context, newConfig);
    }
  }

  void _startRecording() {
    _heldModifiers.clear();
    _capturedKey = null;
    _capturedModifiers.clear();
    setState(() => _isRecording = true);
  }

  void _cancelRecording() {
    _heldModifiers.clear();
    _capturedKey = null;
    _capturedModifiers.clear();
    setState(() => _isRecording = false);
  }

  Future<void> _resetToDefault() async {
    const defaultConfig = HotkeyConfig.defaultConfig;
    await SettingsService.saveHotkeyConfig(defaultConfig);
    if (mounted) {
      setState(() => _currentConfig = defaultConfig);
      Navigator.pop(context, defaultConfig);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _currentConfig;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Hotkey section ─────────────────────────────────────────
          const Text(
            '全局快捷键',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '设置用于显示/隐藏窗口的全局快捷键',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _isRecording ? _buildRecordingUI() : _buildDisplayUI(config),
            ),
          ),

          const SizedBox(height: 16),

          if (!_isRecording) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.edit),
                    label: const Text('修改热键'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restore),
                    label: const Text('恢复默认'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelRecording,
                child: const Text('取消'),
              ),
            ),
          ],

          const SizedBox(height: 40),

          // ── Server address section ────────────────────────────────
          const Text(
            '服务器地址',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '留空使用默认地址，修改后重启生效',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serverController,
            decoration: const InputDecoration(
              hintText: 'http://your-server:8080',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final url = _serverController.text.trim();
                await SettingsService.saveApiBaseUrl(url);
                if (mounted) {
                  setState(() => _savedServerAddr = url);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已保存，重启后生效')),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('保存服务器地址'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayUI(HotkeyConfig? config) {
    return Column(
      children: [
        const Icon(Icons.keyboard, size: 40, color: Colors.blueGrey),
        const SizedBox(height: 12),
        Text(
          config?.displayText ?? '未配置',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          config != null ? '当前热键组合' : '使用默认热键 Ctrl + Shift + S',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildRecordingUI() {
    // Build display of what the user is pressing right now.
    final parts = <String>[];
    for (final mod in _heldModifiers) {
      final label = modifierKeyToConfigLabel(mod);
      if (label != null) {
        switch (label) {
          case 'ctrl':
            parts.add('Ctrl');
            break;
          case 'shift':
            parts.add('Shift');
            break;
          case 'alt':
            parts.add('Alt');
            break;
        }
      }
    }
    if (_capturedKey != null) {
      final keyLabel = physicalKeyToConfigLabel(_capturedKey!);
      if (keyLabel != null) {
        parts.add(HotkeyConfig(
          keyLabel: keyLabel,
          keyCode: 0,
          modifiers: const [],
        ).displayText.split(' + ').last);
      }
    }

    final displayText = parts.isEmpty ? '...' : parts.join(' + ');

    return Column(
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.keyboard, size: 40, color: Colors.orange),
        const SizedBox(height: 12),
        const Text(
          '请按下新的快捷键组合...',
          style: TextStyle(fontSize: 16, color: Colors.orange, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        Text(
          displayText,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        Text(
          '按住修饰键 (Ctrl/Shift/Alt) + 字母/数字键，然后松开',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
