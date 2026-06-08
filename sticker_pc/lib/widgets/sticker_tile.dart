import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StickerTile extends StatefulWidget {
  final String? localPath;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const StickerTile({
    super.key,
    this.localPath,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<StickerTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[200],
          border: _hovered && widget.onTap != null
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            if (_hovered && widget.onTap != null)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(Icons.copy, color: Colors.white, size: 28),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.onTap != null) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: tile,
      );
    }
    return tile;
  }

  Widget _buildImage() {
    if (widget.localPath != null && widget.localPath!.isNotEmpty) {
      return Image.file(
        File(widget.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 32));
  }
}
