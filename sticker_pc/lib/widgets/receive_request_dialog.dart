import 'package:flutter/material.dart';
import '../services/lan/lan_models.dart';

class ReceiveRequestDialog extends StatelessWidget {
  final LanTransferRequest request;
  const ReceiveRequestDialog({super.key, required this.request});

  static Future<bool> show(BuildContext context, LanTransferRequest request) async {
    final result = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => ReceiveRequestDialog(request: request),
    );
    return result ?? false;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('收到传输请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${request.senderName} 想发送给你:'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.folder_zip, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.packName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${request.stickerCount} 个表情',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              )),
            ]),
          ),
          if (request.totalSizeBytes > 0) ...[
            const SizedBox(height: 8),
            Text('大小: ${_formatSize(request.totalSizeBytes)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('拒绝')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('接受')),
      ],
    );
  }
}
