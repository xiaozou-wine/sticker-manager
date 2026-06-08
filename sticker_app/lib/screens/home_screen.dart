import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pack_provider.dart';
import '../models/sticker_pack.dart';
import 'gallery_picker_screen.dart';
import 'pack_detail_screen.dart';
import 'import_link_screen.dart';
import 'share_pack_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PackProvider>().loadPacks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('表情包管理'), centerTitle: true),
      body: Consumer<PackProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());
          if (provider.error != null) return Center(child: Text('加载失败: ${provider.error}'));
          if (provider.packs.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.emoji_emotions_outlined, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('还没有表情包', style: TextStyle(color: Colors.grey, fontSize: 18)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _addFromGallery(context),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('从相册添加'),
                ),
              ]),
            );
          }
          return RefreshIndicator(
            onRefresh: provider.loadPacks,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: provider.packs.length,
              itemBuilder: (context, index) {
                final pack = provider.packs[index];
                return _PackCard(
                  pack: pack,
                  onTap: () => _openPackDetail(context, pack),
                  onLongPress: () => _showDeleteDialog(context, pack),
                  onShare: () => _sharePack(context, pack),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('从相册添加'),
            onTap: () { Navigator.pop(context); _addFromGallery(context); },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('从链接导入'),
            onTap: () { Navigator.pop(context); _importFromLink(context); },
          ),
        ]),
      ),
    );
  }

  Future<void> _addFromGallery(BuildContext context) async {
    final result = await Navigator.push<List<File>>(
      context,
      MaterialPageRoute(builder: (_) => const GalleryPickerScreen()),
    );
    if (result != null && result.isNotEmpty && mounted) {
      _showCreatePackDialog(context, result);
    }
  }

  void _importFromLink(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportLinkScreen()));
  }

  void _openPackDetail(BuildContext context, StickerPack pack) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PackDetailScreen(pack: pack)))
        .then((_) { if (mounted) context.read<PackProvider>().loadPacks(); });
  }

  void _sharePack(BuildContext context, StickerPack pack) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SharePackScreen(pack: pack)));
  }

  void _showDeleteDialog(BuildContext context, StickerPack pack) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除表情包集'),
        content: Text('确定要删除「${pack.name}」吗？\n共 ${pack.stickerCount} 个表情包'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () { context.read<PackProvider>().deletePack(pack.id); Navigator.pop(ctx); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showCreatePackDialog(BuildContext context, List<File> files) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建表情包集'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '输入名称', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final provider = context.read<PackProvider>();
              final pack = await provider.createPack(name);
              if (mounted) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PackDetailScreen(pack: pack, initialFiles: files),
                )).then((_) => provider.loadPacks());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  final StickerPack pack;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onShare;
  const _PackCard({required this.pack, required this.onTap, required this.onLongPress, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _buildCover(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pack.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${pack.stickerCount} 个表情', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                if (pack.shareCode != null) ...[
                  const SizedBox(height: 2),
                  Text('分享码: ${pack.shareCode}', style: TextStyle(fontSize: 12, color: Colors.blue[400])),
                ],
              ]),
            ),
            IconButton(icon: const Icon(Icons.share, size: 20), onPressed: onShare, tooltip: '分享'),
          ]),
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (pack.coverLocal != null && pack.coverLocal!.isNotEmpty) {
      final file = File(pack.coverLocal!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover),
        );
      }
    }
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.emoji_emotions, color: Colors.grey, size: 32),
    );
  }
}
