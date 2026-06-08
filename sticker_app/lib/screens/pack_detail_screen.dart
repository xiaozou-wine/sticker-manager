import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../providers/sticker_provider.dart';
import '../providers/pack_provider.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';
import '../widgets/sticker_grid.dart';
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
        SnackBar(content: Text('导入失败: $e')),
      );
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
          if (_isImporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
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
            onStickerLongPress: (sticker) => _showDeleteStickerDialog(sticker),
          );
        },
      ),
    );
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
}
