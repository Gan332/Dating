import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../data/cover_store.dart';

/// 「去挑一张图」：返回新的封面文件名，用户取消返回 `null`，失败抛异常。
typedef CoverPickRequest = Future<String?> Function();

/// 编辑器从外部拿到的选图回调。
///
/// 参数是这条记录（或这条内置条目改动）的稳定标识：封面文件名带着它，
/// 换机之后文件名仍然与记录对得上。编辑器自己不碰相册插件，也不碰文件系统。
typedef CoverPickCallback = Future<String?> Function(String id);

/// 按文件名显示封面图。
///
/// 图片要异步去私有目录里找：找不到就整块不显示，而不是占一个灰色空框 ——
/// 导入备份会把封面字段清空，系统也可能清理掉文件，那时「没有封面」是事实，
/// 不是加载失败。
class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.store, required this.filename});

  final CoverStore store;

  /// 文件名（不含路径），来自记录的 `coverPath`。
  final String filename;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了封面（文件名变了）要重新取，否则还显示上一张。
    if (oldWidget.filename != widget.filename) _load();
  }

  Future<void> _load() async {
    final file = await widget.store.resolve(widget.filename);
    if (!mounted) return;
    setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        // 相册里的原图可能有几 MB，按显示宽度解码就够，别整张塞进内存。
        child: Image.file(file, fit: BoxFit.cover, cacheWidth: 1080),
      ),
    );
  }
}

/// 编辑器里的封面区块：预览 + 选择/更换 + 移除。
///
/// 只改表单状态，不落盘也不落库：文件名由外面的表单持有，跟着「保存」一起提交。
/// 已经选好的图即使不保存也留在私有目录里，没人再引用的那些由启动清理扫掉
/// （`AppController` 的 `_sweepCovers`），所以「移除」只是把字段清空。
class CoverField extends StatefulWidget {
  const CoverField({
    super.key,
    required this.store,
    required this.filename,
    required this.onPick,
    required this.onChanged,
  });

  final CoverStore store;

  /// 当前选中的封面文件名；为 `null` 表示这条记录还没有封面。
  final String? filename;

  /// 弹选择器并把图复制进私有目录；由调用方提供（界面层转给 `AppController`）。
  final CoverPickRequest onPick;

  /// 用户换了图（新的文件名）或点了移除（`null`）。
  final ValueChanged<String?> onChanged;

  @override
  State<CoverField> createState() => _CoverFieldState();
}

class _CoverFieldState extends State<CoverField> {
  /// 选择器开着的时候挡住第二次点击 —— 相册在部分机型上要给几次返回才退干净，
  /// 连点两下会同时复制两份文件。
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final name = await widget.onPick();
      // 用户取消（null）时保持原样：不能把原来那张封面顺手清掉。
      if (!mounted || name == null) return;
      widget.onChanged(name);
    } catch (error) {
      if (!mounted) return;
      // 选图与复制失败的消息本来就是给用户看的中文（CoverPickException /
      // CoverStoreException 的 toString 就是 message），原样弹出来即可。
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filename = widget.filename;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('封面', style: theme.textTheme.titleSmall),
            const Spacer(),
            // 没有封面时不给「移除」，免得出现一个点了没反应的按钮。
            if (filename != null)
              TextButton.icon(
                onPressed: _busy ? null : () => widget.onChanged(null),
                icon: const Icon(Icons.hide_image_outlined, size: 18),
                label: const Text('移除'),
              ),
          ],
        ),
        if (filename != null) ...[
          CoverImage(store: widget.store, filename: filename),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(filename == null ? '选择封面' : '更换封面'),
          ),
        ),
        if (filename == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '封面只留在这台设备上，不会上传。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
