import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../providers/sticker_provider.dart';
import '../providers/pack_provider.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';
import '../widgets/sticker_grid.dart';
import '../services/storage_service.dart';
import '../services/gallery_save_service.dart';
import '../services/clipboard_service.dart';
import 'gallery_picker_screen.dart';

class PackDetailScreen extends StatefulWidget {
  final StickerPack pack;
  final List<File>? initialFiles;

  const PackDetailScreen({super.key, required this.pack, this.initialFiles});

  @override
  State<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends State<PackDetailScreen> {
  bool _isImporting = false;
  bool _isSaving = false;
  int _saveCurrent = 0;
  int _saveTotal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StickerProvider>().loadStickers(widget.pack.id);
      if (widget.initialFiles != null && widget.initialFiles!.isNotEmpty) {
        _importFiles(widget.initialFiles!);
      }
    });
  }

  Future<void> _importFiles(List<File> files) async {
    setState(() => _isImporting = true);
    final provider = context.read<StickerProvider>();
    final packProvider = context.read<PackProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final packDir = Directory(p.join(appDir.path, 'stickers', widget.pack.id));
      if (!await packDir.exists()) {
        await packDir.create(recursive: true);
      }

      final stickers = <Sticker>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final ext = p.extension(file.path).toLowerCase();
        final stickerId = '${widget.pack.id}_${DateTime.now().microsecondsSinceEpoch}_$i';
        final savePath = p.join(packDir.path, '$stickerId$ext');
        await file.copy(savePath);

        final sticker = Sticker(
          id: stickerId,
          packId: widget.pack.id,
          type: ext == '.gif' ? 'gif' : 'image',
          extension: ext.isEmpty ? '.png' : ext,
          localPath: savePath,
        );
        stickers.add(sticker);
      }

      await provider.addStickers(widget.pack.id, stickers);
      packProvider.refreshPack(widget.pack.id);
      messenger.showSnackBar(
        SnackBar(content: Text('已添加 ${stickers.length} 个表情')),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('导入失败，请检查文件')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ClipboardService.isDesktop;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pack.name),
        actions: [
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('$_saveCurrent/$_saveTotal', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ],
              ),
            )
          else if (!_isImporting) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _renamePack,
              tooltip: '重命名',
            ),
            IconButton(
              icon: Icon(isDesktop ? Icons.folder_open : Icons.save_alt),
              onPressed: isDesktop ? _exportToFolder : _confirmSaveToGallery,
              tooltip: isDesktop ? '导出到文件夹' : '保存到相册',
            ),
          ],
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_isSaving)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _addMore,
              tooltip: '添加表情',
            ),
        ],
      ),
      body: Consumer<StickerProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return StickerGrid(
            stickers: provider.stickers,
            onStickerTap: isDesktop ? (sticker) => _copySticker(sticker) : null,
            onStickerLongPress: (sticker) => _showDeleteStickerDialog(sticker),
          );
        },
      ),
    );
  }

  Future<void> _copySticker(Sticker sticker) async {
    if (sticker.localPath == null) return;
    try {
      await ClipboardService.copyImage(sticker.localPath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板，Ctrl+V 粘贴到聊天窗口'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('复制失败: $e')),
        );
      }
    }
  }

  Future<void> _addMore() async {
    final result = await Navigator.push<List<File>>(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryPickerScreen(targetPackId: widget.pack.id),
      ),
    );
    if (!context.mounted) return;
    if (result != null && result.isNotEmpty) {
      _importFiles(result);
    }
  }

  void _renamePack() {
    final controller = TextEditingController(text: widget.pack.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入新名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == widget.pack.name) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              widget.pack.name = newName;
              final storage = context.read<StorageService>();
              await storage.updatePack(widget.pack);
              context.read<PackProvider>().loadPacks();
              if (mounted) setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteStickerDialog(Sticker sticker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除表情'),
        content: const Text('确定要删除这个表情吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<StickerProvider>()
                  .deleteSticker(widget.pack.id, sticker.id);
              context.read<PackProvider>().refreshPack(widget.pack.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToFolder() async {
    final dir = await fp.FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;

    final provider = context.read<StickerProvider>();
    final count = provider.stickers.length;
    if (count == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前没有表情可以导出')),
        );
      }
      return;
    }

    setState(() {
      _isSaving = true;
      _saveCurrent = 0;
      _saveTotal = count;
    });

    final messenger = ScaffoldMessenger.of(context);
    int saved = 0;
    int failed = 0;

    try {
      final exportDir = Directory(p.join(dir, widget.pack.name));
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      for (int i = 0; i < provider.stickers.length; i++) {
        final sticker = provider.stickers[i];
        if (sticker.localPath != null) {
          try {
            final src = File(sticker.localPath!);
            if (await src.exists()) {
              final ext = p.extension(sticker.localPath!);
              await src.copy(p.join(exportDir.path, '${sticker.id}$ext'));
              saved++;
            } else {
              failed++;
            }
          } catch (_) {
            failed++;
          }
        } else {
          failed++;
        }
        if (mounted) {
          setState(() {
            _saveCurrent = i + 1;
          });
        }
      }

      if (!mounted) return;
      if (failed == 0) {
        messenger.showSnackBar(
          SnackBar(content: Text('已导出 $saved 个表情到 ${exportDir.path}')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('导出完成：成功 $saved 个，失败 $failed 个')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmSaveToGallery() async {
    final provider = context.read<StickerProvider>();
    final count = provider.stickers.length;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有表情可以保存')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存到相册'),
        content: Text('将 $count 个表情保存到手机相册？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _saveToGallery(count);
    }
  }

  Future<void> _saveToGallery(int total) async {
    setState(() {
      _isSaving = true;
      _saveCurrent = 0;
      _saveTotal = total;
    });

    final storage = StorageService();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await GallerySaveService.savePackToGallery(
        storage,
        widget.pack.id,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _saveCurrent = current;
              _saveTotal = total;
            });
          }
        },
      );

      if (!mounted) return;
      final saved = result['saved'] ?? 0;
      final failed = result['failed'] ?? 0;
      if (failed == 0) {
        messenger.showSnackBar(
          SnackBar(content: Text('已保存 $saved 个表情到相册')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('保存完成：成功 $saved 个，失败 $failed 个')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败，请检查存储权限')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
