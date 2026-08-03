import 'dart:io';
import 'package:flutter/material.dart';
import 'app_updater.dart';

/// 弹出“发现新版本”对话框；用户确认后下载并拉起系统安装器
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.system_update_alt, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Text('发现新版本'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新版本 v${info.versionName}（当前 v${_currentShort(info)}）',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (info.apkSize > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '安装包大小: ${_fmtSize(info.apkSize)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '更新说明',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 6),
                Text(
                  info.notes,
                  style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.white70),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                '更新会下载 APK 并调用系统安装器，请确认允许安装未知来源应用',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  // 下载并安装
  if (!context.mounted) return;
  await _downloadAndInstall(context, info);
}

Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final messenger = ScaffoldMessenger.of(context);
  var failed = false;
  var cancelled = false;
  String? errorMsg;
  File? apkFile;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogCtx, setModalState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('正在下载更新'),
          content: _DownloadProgress(
            info: info,
            onProgress: (received, total) {
              if (dialogCtx.mounted) {
                setModalState(() {});
              }
            },
            onDone: (file) {
              // 下载完成：自动关闭进度框并继续拉起系统安装器
              apkFile = file;
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
            },
            onError: (msg) {
              failed = true;
              errorMsg = msg;
              if (dialogCtx.mounted) setModalState(() {});
            },
            onCancelled: () {
              cancelled = true;
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
            },
          ),
        );
      },
    ),
  );

  if (cancelled) {
    messenger.showSnackBar(
      const SnackBar(content: Text('已取消更新，安装包已清理')),
    );
    return;
  }
  if (failed) {
    messenger.showSnackBar(
      SnackBar(content: Text('更新失败: $errorMsg'), backgroundColor: Colors.redAccent),
    );
    return;
  }
  if (apkFile == null) return;

  try {
    await AppUpdater.installApk(apkFile!);
    messenger.showSnackBar(
      const SnackBar(content: Text('安装包已就绪，请在系统安装器中确认安装')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('无法打开安装器: $e'), backgroundColor: Colors.redAccent),
    );
  }
  // 安装包下次启动由 AppUpdater.cleanupStaleApk 兜底清理
}

class _DownloadProgress extends StatefulWidget {
  final UpdateInfo info;
  final void Function(int received, int total) onProgress;
  final void Function(File file) onDone;
  final void Function(String message) onError;
  final void Function() onCancelled;

  const _DownloadProgress({
    required this.info,
    required this.onProgress,
    required this.onDone,
    required this.onError,
    required this.onCancelled,
  });

  @override
  State<_DownloadProgress> createState() => _DownloadProgressState();
}

class _DownloadProgressState extends State<_DownloadProgress> {
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  bool _cancelled = false;
  bool _failed = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final file = await AppUpdater.downloadApk(
        widget.info,
        (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            _progress = total > 0 ? received / total : 0;
          });
          widget.onProgress(received, total);
        },
        isCancelled: () => _cancelled,
      );
      if (!mounted) return;
      widget.onDone(file); // 父级自动关闭并拉起系统安装器
    } catch (e) {
      if (!mounted) return;
      if (_cancelled) {
        widget.onCancelled();
      } else {
        setState(() {
          _failed = true;
          _errorMsg = e.toString();
        });
        widget.onError(e.toString());
      }
    }
  }

  void _cancel() {
    if (_failed || _cancelled) return;
    setState(() => _cancelled = true);
  }

  String _pct() => _total > 0
      ? '${(_progress * 100).toStringAsFixed(0)}%'
      : '...';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_failed) ...[
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
          const SizedBox(height: 8),
          const Text(
            '下载失败',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _errorMsg ?? '未知错误',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style:
                  FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('关闭'),
            ),
          ),
        ] else if (_cancelled) ...[
          const Text('正在取消…', style: TextStyle(fontSize: 13)),
        ] else ...[
          LinearProgressIndicator(
            value: _progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: Colors.white12,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 10),
          Text(
            'v${widget.info.versionName} · ${_pct()}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_fmtSize(_received)} / ${_fmtSize(_total)}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            '下载完成后会自动拉起系统安装器',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancel,
                child: const Text('取消下载'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _currentShort(UpdateInfo info) => info.versionName;

String _fmtSize(int bytes) {
  if (bytes <= 0) return '未知';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
