import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../providers/pack_provider.dart';
import '../services/storage_service.dart';

class ImportLinkScreen extends StatefulWidget {
  const ImportLinkScreen({super.key});
  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  StickerPackPreview? _preview;
  double _downloadProgress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入表情包')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: '分享码或链接',
                hintText: '输入分享码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _isLoading ? null : _lookup,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('查找'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text(_preview!.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_preview!.count} 个表情'),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isDownloading ? null : _download,
                icon: _isDownloading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_isDownloading ? '下载中...' : '一键下载'),
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _lookup() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() { _isLoading = true; _error = null; _preview = null; });
    try {
      final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
      final pack = await api.getPackByCode(code);
      if (!mounted) return;
      setState(() { _preview = StickerPackPreview(name: pack.name, count: pack.stickerCount, code: code); });
    } catch (e) {
      if (mounted) setState(() { _error = '查找失败: 请检查分享码是否正确'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _download() async {
    if (_preview == null) return;
    setState(() { _isDownloading = true; _downloadProgress = 0; });
    try {
      final storage = context.read<StorageService>();
      final packProvider = context.read<PackProvider>();
      final messenger = ScaffoldMessenger.of(context);
      final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
      final dl = DownloadService(apiService: api, storageService: storage);
      final result = await dl.downloadPack(
        shareCode: _preview!.code,
        packName: _preview!.name,
        onProgress: (done, total) {
          if (mounted) setState(() { _downloadProgress = done / total; });
        },
      );
      if (!mounted) return;
      final msg = result.failedCount > 0
          ? '下载完成，${result.stickerCount} 个成功，${result.failedCount} 个失败'
          : '下载完成，共 ${result.stickerCount} 个表情';
      packProvider.loadPacks();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _error = '下载失败: $e'; });
    } finally {
      if (mounted) setState(() { _isDownloading = false; });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

class StickerPackPreview {
  final String name;
  final int count;
  final String code;
  StickerPackPreview({required this.name, required this.count, required this.code});
}
