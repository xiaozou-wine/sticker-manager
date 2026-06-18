import 'dart:io';
import 'package:flutter/foundation.dart';

/// Windows 防火墙入站规则辅助工具
/// 为局域网互传的 HTTP 端口（53320）添加入站放行规则
class FirewallHelper {
  static const _ruleName = 'Sticker Manager LAN Transfer';
  static const _port = 53320;

  /// 检查并尝试添加防火墙入站规则
  /// 返回 [FirewallResult] 描述结果
  static Future<FirewallResult> ensureRule() async {
    if (!Platform.isWindows) {
      return FirewallResult(FirewallStatus.unsupported);
    }

    // 先检查规则是否已存在
    try {
      final check = await Process.run(
        'netsh',
        ['advfirewall', 'firewall', 'show', 'rule', 'name=$_ruleName'],
        runInShell: true,
      );
      if (check.exitCode == 0 && check.stdout.toString().contains(_ruleName)) {
        debugPrint('[Firewall] Rule already exists');
        return FirewallResult(FirewallStatus.alreadyExists);
      }
    } catch (e) {
      debugPrint('[Firewall] Check failed: $e');
    }

    // 尝试添加规则（需要管理员权限）
    try {
      final result = await Process.run(
        'netsh',
        [
          'advfirewall', 'firewall', 'add', 'rule',
          'name=$_ruleName',
          'dir=in',
          'action=allow',
          'protocol=TCP',
          'localport=$_port',
        ],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        debugPrint('[Firewall] Rule added successfully');
        return FirewallResult(FirewallStatus.added);
      } else {
        debugPrint('[Firewall] Add failed: ${result.stderr}');
        return FirewallResult(FirewallStatus.failed,
            error: result.stderr.toString().trim());
      }
    } catch (e) {
      debugPrint('[Firewall] Add exception: $e');
      return FirewallResult(FirewallStatus.failed, error: e.toString());
    }
  }

  /// 手动添加防火墙规则的说明文本
  static const String manualInstructions = '''
局域网互传需要允许 TCP 端口 $_port 的入站连接。

手动设置步骤：
1. 按 Win 键，搜索"防火墙"，打开"Windows Defender 防火墙"
2. 点击左侧"高级设置"
3. 左侧选择"入站规则" → 右侧点击"新建规则"
4. 选择"端口" → 下一步
5. 选择"TCP"，输入端口 $_port → 下一步
6. 选择"允许连接" → 下一步
7. 勾选所有网络类型 → 下一步
8. 名称填写：$_ruleName → 完成''';
}

enum FirewallStatus {
  /// 非 Windows 平台
  unsupported,

  /// 规则已存在
  alreadyExists,

  /// 规则添加成功
  added,

  /// 添加失败（通常因为非管理员权限）
  failed,
}

class FirewallResult {
  final FirewallStatus status;
  final String? error;

  FirewallResult(this.status, {this.error});

  bool get ok =>
      status == FirewallStatus.alreadyExists ||
      status == FirewallStatus.added ||
      status == FirewallStatus.unsupported;
}
