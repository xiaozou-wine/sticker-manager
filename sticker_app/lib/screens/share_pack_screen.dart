import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/sticker_pack.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class SharePackScreen extends StatefulWidget {
  final StickerPack pack;
  const SharePackScreen({super.key, required this.pack});
  @override
  State<SharePackScreen> createState() => _SharePackScreenState();
}

class _SharePackScreenState extends State<SharePackScreen> {
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _shareCode;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分享表情包')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(widget.pack.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${widget.pack.stickerCount} 个表情'),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            if (_shareCode == null) ...[
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _upload,
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? '上传中...' : '上传并生成分享码'),
              ),
              if (_isUploading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _uploadProgress > 0 ? _uploadProgress : null),
              ],
            ] else ...[
              const Text('分享码:', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_shareCode!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _shareCode!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制分享码'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    setState(() { _isUploading = true; _error = null; _uploadProgress = 0; });
    try {
      final storage = context.read<StorageService>();
      final stickers = await storage.getStickersByPackId(widget.pack.id);
      final files = stickers
          .where((s) => s.localPath != null && s.localPath!.isNotEmpty)
          .map((s) => File(s.localPath!))
          .where((f) => f.existsSync())
          .toList();
      if (files.isEmpty) {
        setState(() { _error = '没有可上传的本地表情文件'; });
        return;
      }
      final api = ApiService(baseUrl: 'http://localhost:8080');
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
      setState(() { _error = '上传失败: $e'; });
    } finally {
      setState(() { _isUploading = false; });
    }
  }
}
