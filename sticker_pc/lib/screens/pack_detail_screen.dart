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
import '../services/clipboard_service.dart';

class PackDetailScreen extends StatefulWidget {
  final StickerPack pack;
  final List<File>? initialFiles;

  const PackDetailScreen({super.key, required this.pack, this.initialFiles});

  @override
  State<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends State<PackDetailScreen> {
  bool _isImporting = false;
  bool _isExporting = false;
  int _exportCurrent = 0;
  int _exportTotal = 0;

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
      if (!await packDir.exists()) await packDir.create(recursive: true);

      final stickers = <Sticker>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final ext = p.extension(file.path).toLowerCase();
        final stickerId = '${widget.pack.id}_${DateTime.now().microsecondsSinceEpoch}_$i';
        final savePath = p.join(packDir.path, '$stickerId$ext');
        await file.copy(savePath);
        stickers.add(Sticker(
          id: stickerId,
          packId: widget.pack.id,
          type: ext == '.gif' ? 'gif' : 'image',
          extension: ext.isEmpty ? '.png' : ext,
          localPath: savePath,
        ));
      }

      await provider.addStickers(widget.pack.id, stickers);
      packProvider.refreshPack(widget.pack.id);
      messenger.showSnackBar(SnackBar(content: Text('已添加 ${stickers.length} 个表情')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('导入失败，请检查文件')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pack.name),
        actions: [
          if (_isExporting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 6),
                Text('$_exportCurrent/$_exportTotal', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
              ]),
            )
          else if (!_isImporting) ...[
            IconButton(icon: const Icon(Icons.edit), onPressed: _renamePack, tooltip: '重命名'),
            IconButton(icon: const Icon(Icons.folder_open), onPressed: _exportToFolder, tooltip: '导出到文件夹'),
          ],
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_isExporting)
            IconButton(icon: const Icon(Icons.add_photo_alternate), onPressed: _addMore, tooltip: '添加表情'),
        ],
      ),
      body: Consumer<StickerProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          return StickerGrid(
            stickers: provider.stickers,
            onStickerTap: (sticker) => _copySticker(sticker),
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
          const SnackBar(content: Text('已复制到剪贴板，Ctrl+V 粘贴到聊天窗口'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('复制失败: $e')));
      }
    }
  }

  Future<void> _addMore() async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      final files = result.paths.where((p) => p != null).map((p) => File(p!)).toList();
      if (files.isNotEmpty && mounted) _importFiles(files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择文件失败: $e')));
      }
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
              if (newName.isEmpty || newName == widget.pack.name) { Navigator.pop(ctx); return; }
              Navigator.pop(ctx);
              widget.pack.name = newName;
              await context.read<StorageService>().updatePack(widget.pack);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              context.read<StickerProvider>().deleteSticker(widget.pack.id, sticker.id);
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
    final dir = await fp.FilePicker.platform.getDirectoryPath(dialogTitle: '选择导出目录');
    if (dir == null) return;

    final provider = context.read<StickerProvider>();
    final count = provider.stickers.length;
    if (count == 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有表情可以导出')));
      return;
    }

    setState(() { _isExporting = true; _exportCurrent = 0; _exportTotal = count; });
    final messenger = ScaffoldMessenger.of(context);
    int saved = 0, failed = 0;

    try {
      final exportDir = Directory(p.join(dir, widget.pack.name));
      if (!await exportDir.exists()) await exportDir.create(recursive: true);

      for (int i = 0; i < provider.stickers.length; i++) {
        final sticker = provider.stickers[i];
        if (sticker.localPath != null) {
          try {
            final src = File(sticker.localPath!);
            if (await src.exists()) {
              await src.copy(p.join(exportDir.path, '${sticker.id}${p.extension(sticker.localPath!)}'));
              saved++;
            } else { failed++; }
          } catch (_) { failed++; }
        } else { failed++; }
        if (mounted) setState(() => _exportCurrent = i + 1);
      }

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(failed == 0 ? '已导出 $saved 个表情到 ${exportDir.path}' : '导出完成：成功 $saved 个，失败 $failed 个'),
      ));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('导出失败: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
