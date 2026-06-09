import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/sticker_pack.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

class SharePackScreen extends StatefulWidget {
  final StickerPack pack;
  const SharePackScreen({super.key, required this.pack});
  @override
  State<SharePackScreen> createState() => _SharePackScreenState();
}

enum _ShareMode { central, vps }

class _SharePackScreenState extends State<SharePackScreen> {
  _ShareMode _mode = _ShareMode.central;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;
  String? _shareCode;
  final _serverController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _vpsShareLink;

  @override
  void initState() {
    super.initState();
    if (widget.pack.shareCode != null && widget.pack.shareCode!.isNotEmpty) {
      _shareCode = widget.pack.shareCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分享表情包')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(widget.pack.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${widget.pack.stickerCount} 个表情'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_ShareMode>(
              segments: const [
                ButtonSegment(value: _ShareMode.central, label: Text('服务器分享码'), icon: Icon(Icons.dns)),
                ButtonSegment(value: _ShareMode.vps, label: Text('VPS 加密分享'), icon: Icon(Icons.lock)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() { _mode = s.first; _error = null; }),
            ),
            const SizedBox(height: 20),
            if (_mode == _ShareMode.central) _buildCentralSection(),
            if (_mode == _ShareMode.vps) _buildVPSSection(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCentralSection() {
    if (_shareCode != null) {
      return Column(children: [
        const Text('分享码:', style: TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_shareCode!,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
              textAlign: TextAlign.center),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _shareCode!));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('复制分享码'),
        ),
      ]);
    }
    return ElevatedButton.icon(
      onPressed: _isUploading ? null : _uploadToCentral,
      icon: _isUploading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cloud_upload),
      label: Text(_isUploading ? '上传中...' : '上传并生成分享码'),
    );
  }

  Widget _buildVPSSection() {
    if (_vpsShareLink != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('分享链接（端到端加密）',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                const SizedBox(height: 8),
                SelectableText(_vpsShareLink!,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('链接中 # 后面的密钥不会发送到服务器，只有拥有链接的人才能解密。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _vpsShareLink!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制分享链接'),
          ),
        ],
      );
    }
    final isHttp = _serverController.text.trim().toLowerCase().startsWith('http://');
    return Column(
      children: [
        TextField(
          controller: _serverController,
          decoration: const InputDecoration(
            labelText: 'VPS 地址',
            hintText: 'http://your-vps:28749',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
        ),
        if (isHttp) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('HTTP 连接不加密，密码将以明文传输。建议使用 HTTPS。',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        if (_isUploading) ...[
          LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
          const SizedBox(height: 8),
          Text('加密并上传中...', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
        ],
        ElevatedButton.icon(
          onPressed: _isUploading ? null : _uploadToVPS,
          icon: _isUploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock),
          label: Text(_isUploading ? '加密上传中...' : '加密上传到 VPS'),
        ),
      ],
    );
  }

  Future<void> _uploadToCentral() async {
    setState(() { _isUploading = true; _error = null; });
    try {
      final storage = context.read<StorageService>();
      final stickers = await storage.getStickersByPackId(widget.pack.id);
      final files = stickers
          .where((s) => s.localPath != null && File(s.localPath!).existsSync())
          .map((s) => File(s.localPath!))
          .toList();
      if (files.isEmpty) {
        setState(() { _error = '没有可上传的表情文件'; });
        return;
      }
      final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
      final result = await api.uploadPack(
        name: widget.pack.name,
        description: widget.pack.description,
        images: files,
        onSendProgress: (sent, total) {
          if (total > 0) setState(() { _uploadProgress = sent / total; });
        },
      );
      widget.pack.shareCode = result.pack.shareCode;
      widget.pack.isUploaded = true;
      await storage.updatePack(widget.pack);
      setState(() { _shareCode = result.pack.shareCode; });
    } catch (e) {
      setState(() { _error = '上传失败，请检查网络连接'; });
    } finally {
      setState(() { _isUploading = false; });
    }
  }

  Future<void> _uploadToVPS() async {
    final serverAddr = _serverController.text.trim();
    final password = _passwordController.text.trim();
    if (serverAddr.isEmpty || password.isEmpty) {
      setState(() { _error = '请填写 VPS 地址和密码'; });
      return;
    }
    setState(() { _isUploading = true; _error = null; _uploadProgress = 0; });
    try {
      final storage = context.read<StorageService>();
      final stickers = await storage.getStickersByPackId(widget.pack.id);
      final files = stickers
          .where((s) => s.localPath != null && File(s.localPath!).existsSync())
          .map((s) => File(s.localPath!))
          .toList();
      if (files.isEmpty) {
        setState(() { _error = '没有可上传的表情文件'; });
        return;
      }

      final key = CryptoService.generateKey();
      final tempDir = Directory.systemTemp.createTempSync('sticker_enc_');
      try {
        final encryptedFiles = <File>[];
        for (final file in files) {
          final plaintext = await file.readAsBytes();
          final encrypted = CryptoService.encryptData(plaintext, key);
          final encFile = File('${tempDir.path}/${file.uri.pathSegments.last}.enc');
          await encFile.writeAsBytes(encrypted);
          encryptedFiles.add(encFile);
        }

        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final result = await api.uploadPack(
          name: widget.pack.name,
          description: widget.pack.description,
          images: encryptedFiles,
          customBaseUrl: serverAddr,
          authToken: password,
          onSendProgress: (sent, total) {
            if (total > 0) setState(() { _uploadProgress = sent / total; });
          },
        );

        final link = CryptoService.buildShareLink(
          serverAddr: serverAddr,
          packId: result.pack.id,
          shareCode: (result.pack.shareCode ?? 'unknown'),
          key: key,
        );

        widget.pack.shareCode = result.pack.shareCode;
        widget.pack.isUploaded = true;
        if (!mounted) return;
        final storage2 = context.read<StorageService>();
        await storage2.updatePack(widget.pack);

        setState(() { _vpsShareLink = link; });
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    } catch (e) {
      setState(() { _error = '上传失败，请检查网络连接'; });
    } finally {
      setState(() { _isUploading = false; });
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
