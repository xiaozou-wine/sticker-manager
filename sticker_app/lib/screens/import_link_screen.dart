import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import '../config.dart';
import '../models/sticker.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/download_service.dart';
import '../services/gallery_save_service.dart';
import '../providers/pack_provider.dart';
import '../services/storage_service.dart';

class ImportLinkScreen extends StatefulWidget {
  final String? initialLink;
  const ImportLinkScreen({super.key, this.initialLink});
  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  _PackPreview? _preview;
  double _downloadProgress = 0;
  ShareLinkInfo? _parsedLink;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      _codeController.text = widget.initialLink!;
      // 延迟自动查找
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入表情包')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: '分享码或链接',
                hintText: '粘贴 sticker://share/... 或输入分享码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: '从剪贴板粘贴',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _codeController.text = data!.text!;
                    }
                  },
                ),
              ),
              maxLines: 3,
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
                    Text(_preview!.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${_preview!.count} 个表情'),
                    if (_parsedLink != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('端到端加密',
                            style: TextStyle(fontSize: 12, color: Colors.green)),
                      ),
                    ],
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
    final input = _codeController.text.trim();
    if (input.isEmpty) return;
    setState(() { _isLoading = true; _error = null; _preview = null; _parsedLink = null; });
    try {
      final parsed = CryptoService.parseShareLink(input);
      if (parsed != null) {
        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final pack = await api.getPackByCodeFromServer(parsed.shareCode, parsed.serverAddr);
        if (!mounted) return;
        setState(() {
          _parsedLink = parsed;
          _preview = _PackPreview(name: pack.name, count: pack.stickerCount, code: parsed.shareCode);
        });
      } else {
        final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
        final pack = await api.getPackByCode(input);
        if (!mounted) return;
        setState(() {
          _preview = _PackPreview(name: pack.name, count: pack.stickerCount, code: input);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '查找失败: 请检查链接或分享码是否正确'; });
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
      if (_parsedLink != null) {
        await _downloadEncrypted(storage, packProvider, messenger);
      } else {
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
      }
    } catch (e) {
      if (mounted) setState(() { _error = '下载失败: $e'; });
    } finally {
      if (mounted) setState(() { _isDownloading = false; });
    }
  }

  Future<void> _downloadEncrypted(
      StorageService storage, PackProvider packProvider, ScaffoldMessengerState messenger) async {
    final link = _parsedLink!;
    final api = ApiService(baseUrl: AppConfig.apiBaseUrl);
    final pack = await api.getPackByCodeFromServer(link.shareCode, link.serverAddr);
    final remoteStickers = await api.getPackStickersFromServer(link.shareCode, link.serverAddr);
    if (remoteStickers.isEmpty) {
      setState(() { _error = '远程包为空'; });
      return;
    }
    pack.source = 'link';
    await storage.insertPack(pack);

    final appDir = await getApplicationDocumentsDirectory();
    final packDir = Directory(p.join(appDir.path, 'stickers', pack.id));
    if (!await packDir.exists()) await packDir.create(recursive: true);

    final stickers = <Sticker>[];
    final importedHashes = <String>[];
    int failedCount = 0;
    for (int i = 0; i < remoteStickers.length; i++) {
      final remote = remoteStickers[i];
      try {
        final tempPath = p.join(packDir.path, '${remote.id}.enc');
        await api.downloadSticker(remote.fileUrl, tempPath);
        final encData = await File(tempPath).readAsBytes();
        final decData = CryptoService.decryptData(encData, link.key);
        var ext = _guessExtension(decData);
        var saveData = decData;
        if (ext == '.webp') {
          final converted = _convertWebpToPng(decData);
          if (converted != null) {
            saveData = Uint8List.fromList(converted);
            ext = '.png';
            debugPrint('WebP→PNG 转换成功: ${remote.id}');
          } else {
            debugPrint('WebP→PNG 转换失败，保留原始 WebP: ${remote.id}');
          }
        }
        final localPath = p.join(packDir.path, '${remote.id}$ext');
        await File(localPath).writeAsBytes(saveData);
        await File(tempPath).delete();

        // 记录 hash（链接导入时已同时保存到相册）
        importedHashes.add(sha256.convert(saveData).toString());

        // Save to phone gallery (Android only, best-effort)
        if (Platform.isAndroid) {
          try {
            await Gal.putImage(localPath, album: 'StickerApp/${pack.name}');
          } catch (_) {}
        }

        stickers.add(Sticker(
          id: remote.id, packId: pack.id, type: remote.type,
          width: remote.width, height: remote.height,
          sizeBytes: saveData.length, extension: ext, localPath: localPath,
        ));
        if (mounted) setState(() { _downloadProgress = (i + 1) / remoteStickers.length; });
      } catch (e) {
        failedCount++;
      }
    }

    if (stickers.isNotEmpty) {
      await storage.insertStickers(stickers);
      await storage.updatePackStickerCount(pack.id);
      pack.coverLocal = stickers.first.localPath;
      pack.coverUrl = remoteStickers.first.fileUrl;
      await storage.updatePack(pack);
      // 导入时记录 hash，标记已保存到相册
      if (Platform.isAndroid) {
        await GallerySaveService.recordImportHashes(pack.id, importedHashes, savedToGallery: true);
      }
    }

    if (!mounted) return;
    if (stickers.isEmpty) {
      setState(() { _error = '下载/解密失败，请检查链接是否正确'; });
      return;
    }
    final msg = failedCount > 0
        ? '下载完成，${stickers.length} 个成功，$failedCount 个失败'
        : '下载完成，共 ${stickers.length} 个表情';
    packProvider.loadPacks();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  String _guessExtension(List<int> data) {
    if (data.length >= 4) {
      if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return '.png';
      if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) return '.gif';
      if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return '.jpg';
      if (data.length >= 12 &&
          data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
          data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) {
        return '.webp';
      }
    }
    return '.png';
  }

  List<int>? _convertWebpToPng(Uint8List webpData) {
    try {
      final decoded = img.decodeImage(webpData);
      if (decoded == null) return null;
      return img.encodePng(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

class _PackPreview {
  final String name;
  final int count;
  final String code;
  _PackPreview({required this.name, required this.count, required this.code});
}
