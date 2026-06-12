import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pack_provider.dart';
import '../models/sticker_pack.dart';
import '../services/clipboard_service.dart';
import 'gallery_picker_screen.dart';
import 'album_picker_screen.dart';
import 'pack_detail_screen.dart';
import 'import_link_screen.dart';
import 'share_pack_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<File>? sharedFiles;
  const HomeScreen({super.key, this.sharedFiles});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PackProvider>();
      provider.loadSortMode().then((_) => provider.loadPacks());
      if (widget.sharedFiles != null && widget.sharedFiles!.isNotEmpty) {
        _showCreatePackDialog(context, widget.sharedFiles!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('表情包管理'),
        centerTitle: true,
        actions: [
          _buildSortButton(),
        ],
      ),
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
                  label: Text(ClipboardService.isDesktop ? '从文件添加' : '从相册添加'),
                ),
              ]),
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: provider.packs.length,
            onReorderItem: (oldIndex, newIndex) {
              provider.reorderPacks(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final pack = provider.packs[index];
              return _PackCard(
                key: ValueKey(pack.id),
                pack: pack,
                onTap: () => _openPackDetail(context, pack),
                onShare: () => _sharePack(context, pack),
                onDelete: () => _showDeleteDialog(context, pack),
              );
            },
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

  Widget _buildSortButton() {
    return Consumer<PackProvider>(
      builder: (context, provider, _) {
        return PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: '排序',
          onSelected: (mode) => provider.setSortMode(mode),
          itemBuilder: (_) => [
            _sortItem('updated', '最近更新', Icons.access_time, provider.sortMode),
            _sortItem('created', '创建时间', Icons.calendar_today, provider.sortMode),
            _sortItem('name', '名称', Icons.sort_by_alpha, provider.sortMode),
            _sortItem('count', '表情数量', Icons.numbers, provider.sortMode),
          ],
        );
      },
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label, IconData icon, String current) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 20, color: current == value ? Theme.of(context).colorScheme.primary : null),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          fontWeight: current == value ? FontWeight.bold : FontWeight.normal,
          color: current == value ? Theme.of(context).colorScheme.primary : null,
        )),
        if (current == value) ...[
          const Spacer(),
          Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
        ],
      ]),
    );
  }

  void _showAddOptions(BuildContext homeContext) {
    final isDesktop = ClipboardService.isDesktop;
    showModalBottomSheet(
      context: homeContext,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(isDesktop ? Icons.folder_open : Icons.photo_library),
            title: Text(isDesktop ? '从文件添加' : '从相册添加'),
            onTap: () { Navigator.pop(context); _addFromGallery(homeContext); },
          ),
          if (!isDesktop)
            ListTile(
              leading: const Icon(Icons.collections),
              title: const Text('从相册批量导入'),
              subtitle: const Text('选择一个相册，导入全部照片'),
              onTap: () { Navigator.pop(context); _importFromAlbum(homeContext); },
            ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('从链接导入'),
            onTap: () { Navigator.pop(context); _importFromLink(homeContext); },
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
    if (result != null && result.isNotEmpty) {
      if (!context.mounted) return;
      _showCreatePackDialog(context, result);
    }
  }

  void _importFromLink(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportLinkScreen()));
  }

  Future<void> _importFromAlbum(BuildContext context) async {
    final result = await Navigator.push<List<File>>(
      context,
      MaterialPageRoute(builder: (_) => const AlbumPickerScreen()),
    );
    if (result != null && result.isNotEmpty) {
      if (!context.mounted) return;
      _showCreatePackDialog(context, result);
    }
  }

  void _openPackDetail(BuildContext context, StickerPack pack) {
    final provider = context.read<PackProvider>();
    Navigator.push(context, MaterialPageRoute(builder: (_) => PackDetailScreen(pack: pack)))
        .then((_) => provider.loadPacks());
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
              if (!context.mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PackDetailScreen(pack: pack, initialFiles: files),
              )).then((_) => provider.loadPacks());
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
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const _PackCard({super.key, required this.pack, required this.onTap, required this.onShare, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) {
                if (value == 'share') onShare();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'share', child: Row(children: [Icon(Icons.share, size: 18), SizedBox(width: 8), Text('分享')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (pack.coverLocal != null && pack.coverLocal!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(pack.coverLocal!),
          width: 56, height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        ),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.emoji_emotions, color: Colors.grey, size: 32),
    );
  }
}
