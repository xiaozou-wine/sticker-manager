import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';

/// Displays the UI node tree captured from the accessibility service.
/// Used to find selectors for QQ/WeChat UI elements without ADB.
class UISnapshotScreen extends StatefulWidget {
  const UISnapshotScreen({super.key});

  @override
  State<UISnapshotScreen> createState() => _UISnapshotScreenState();
}

class _UISnapshotScreenState extends State<UISnapshotScreen> {
  List<Map<String, dynamic>> _nodes = [];
  bool _loading = false;
  String _filter = '';
  String _error = '';

  Future<void> _capture() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final nodes = await AccessibilityService.dumpNodeTree();
      setState(() {
        _nodes = nodes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '抓取失败，请确保无障碍服务已开启，且已切换到 QQ/微信界面';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredNodes {
    if (_filter.isEmpty) return _nodes;
    final lower = _filter.toLowerCase();
    return _nodes.where((n) {
      return (n['text'] as String? ?? '').toLowerCase().contains(lower) ||
          (n['desc'] as String? ?? '').toLowerCase().contains(lower) ||
          (n['vid'] as String? ?? '').toLowerCase().contains(lower) ||
          (n['class'] as String? ?? '').toLowerCase().contains(lower) ||
          (n['id'] as String? ?? '').toLowerCase().contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 节点快照'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: '抓取当前界面',
            onPressed: _loading ? null : _capture,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildHintBar(),
          if (_error.isNotEmpty) _buildError(),
          Expanded(child: _buildNodeList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索 text / desc / vid / class ...',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: _filter.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _filter = ''),
                )
              : null,
        ),
        onChanged: (v) => setState(() => _filter = v),
      ),
    );
  }

  Widget _buildHintBar() {
    if (_nodes.isEmpty && !_loading) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.blue[50],
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _filter.isEmpty
                  ? '共 ${_nodes.length} 个节点 · 点击节点复制选择器'
                  : '匹配 ${_filteredNodes.length} / ${_nodes.length} 个节点',
              style: TextStyle(fontSize: 12, color: Colors.blue[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red[50],
      child: Text(_error, style: TextStyle(color: Colors.red[700], fontSize: 13)),
    );
  }

  Widget _buildNodeList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '打开 QQ 或微信的聊天窗口\n然后点击右上角相机按钮抓取',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredNodes;
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) => _NodeTile(node: filtered[index]),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final Map<String, dynamic> node;
  const _NodeTile({required this.node});

  @override
  Widget build(BuildContext context) {
    final depth = node['depth'] as int? ?? 0;
    final className = (node['class'] as String? ?? '').split('.').last;
    final text = node['text'] as String? ?? '';
    final desc = node['desc'] as String? ?? '';
    final vid = node['vid'] as String? ?? '';
    final fullId = node['id'] as String? ?? '';
    final editable = node['editable'] as bool? ?? false;
    final clickable = node['clickable'] as bool? ?? false;
    final visible = node['visible'] as bool? ?? false;
    final bounds = node['bounds'] as String? ?? '';

    // Build selector string
    final selector = _buildSelector();

    return InkWell(
      onTap: () => _copySelector(context, selector),
      child: Container(
        padding: EdgeInsets.only(left: 8.0 + depth * 16, right: 8, top: 6, bottom: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          color: editable ? Colors.green[50] : (clickable ? Colors.blue[50] : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: class name + badges
            Row(
              children: [
                Text(
                  className,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                if (editable) ...[
                  const SizedBox(width: 6),
                  _badge('EDITABLE', Colors.green),
                ],
                if (clickable) ...[
                  const SizedBox(width: 6),
                  _badge('CLICKABLE', Colors.blue),
                ],
                if (visible) ...[
                  const SizedBox(width: 6),
                  _badge('VIS', Colors.orange),
                ],
                const Spacer(),
                Text(
                  bounds,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
            // Row 2: text / desc / vid
            if (text.isNotEmpty)
              _propRow('text', '"$text"', Colors.purple),
            if (desc.isNotEmpty)
              _propRow('desc', '"$desc"', Colors.teal),
            if (vid.isNotEmpty)
              _propRow('vid', vid, Colors.indigo),
            if (fullId.isNotEmpty && fullId != vid)
              _propRow('id', fullId, Colors.indigo[300]!),
            // Row 3: selector hint
            if (selector.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '→ $selector',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _buildSelector() {
    final vid = node['vid'] as String? ?? '';
    final text = node['text'] as String? ?? '';
    final desc = node['desc'] as String? ?? '';
    final editable = node['editable'] as bool? ?? false;

    // Prioritize: vid > text > desc
    if (editable) {
      if (vid.isNotEmpty) return 'EditText[vid="$vid"]';
      return 'EditText';
    }
    if (vid.isNotEmpty) return '[vid="$vid"]';
    if (text.isNotEmpty) return '[text="$text"]';
    if (desc.isNotEmpty) return '[desc="$desc"]';
    return '';
  }

  void _copySelector(BuildContext context, String selector) {
    if (selector.isEmpty) return;
    // Copy to clipboard would need Clipboard.setData
    // For now, show in a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('选择器: $selector', style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: '知道了', onPressed: () {}),
      ),
    );
  }

  Widget _propRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
