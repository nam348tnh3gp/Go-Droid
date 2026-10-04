import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/run_result.dart';
import '../models/tab_data.dart';
import '../widgets/code_editor.dart';
import '../widgets/output_panel.dart';
import '../widgets/ai_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

class EditorScreen extends StatefulWidget {
  @override
  _EditorScreenState createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  RunResult? _result;
  bool _isRunning = false;
  bool _isGenerating = false;

  /// Tỉ lệ chiều cao vùng Output so với phần body còn lại (đã trừ tab bar).
  double _outputFraction = 0.38;

  /// Vị trí con trỏ — dùng ValueNotifier để không rebuild cả screen.
  final ValueNotifier<EditorPosition?> _cursor =
      ValueNotifier<EditorPosition?>(null);

  bool get _isBusy => _isRunning || _isGenerating;

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  String _stripCodeFence(String raw) {
    var text = raw.trim();
    final fenceMatch = RegExp(
      r'^```[ \t]*[a-zA-Z]*[ \t]*\r?\n([\s\S]*?)\r?\n?```[ \t]*$',
    ).firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1) ?? text;
    } else {
      text = text.replaceFirst(RegExp(r'^```[ \t]*[a-zA-Z]*[ \t]*\r?\n'), '');
      text = text.replaceFirst(RegExp(r'\r?\n?```[ \t]*$'), '');
    }
    return text.trim();
  }

  Future<void> _runCode() async {
    final appState = context.read<AppState>();
    final currentTab = appState.currentTab;
    if (currentTab == null) return;

    setState(() => _isRunning = true);

    final url = appState.backendUrl;
    final payload = <String, dynamic>{
      'code': currentTab.code,
      if (currentTab.goMod != null && currentTab.goMod!.isNotEmpty)
        'goMod': currentTab.goMod,
    };

    try {
      final response = await http.post(
        Uri.parse('$url/run'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _result = RunResult.fromJson(data, response.statusCode == 200);
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result =
            RunResult(error: 'Không thể kết nối đến backend: $e', success: false);
        _isRunning = false;
      });
    }
  }

  Future<void> _generateCode(String prompt) async {
    final appState = context.read<AppState>();
    final url = appState.backendUrl;

    setState(() => _isGenerating = true);

    try {
      final response = await http.post(
        Uri.parse('$url/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200 && data['code'] != null) {
        final generatedCode = _stripCodeFence(data['code'] as String);
        // Nếu backend trả kèm goMod thì dùng luôn.
        final goMod = data['goMod'] is String &&
                (data['goMod'] as String).trim().isNotEmpty
            ? data['goMod'] as String
            : null;

        appState.addNewTab(
          name: 'generated_${DateTime.now().millisecondsSinceEpoch}.go',
          code: generatedCode,
          goMod: goMod,
        );

        // Nếu code có import ngoài mà chưa có goMod, gợi ý luôn.
        if (goMod == null) {
          final external = appState.detectExternalImports(generatedCode);
          if (external.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Code dùng ${external.length} package ngoài — cần thêm go.mod'),
                action: SnackBarAction(
                  label: 'Tạo',
                  onPressed: () {
                    final tab = appState.currentTab;
                    if (tab != null) _editGoModDialog(tab);
                  },
                ),
              ),
            );
            return;
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Code đã được tạo trong tab mới!')),
        );
      } else {
        setState(() {
          _result = RunResult(
            error: data['error'] ?? 'Không thể sinh code',
            success: false,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = RunResult(error: 'Lỗi kết nối: $e', success: false);
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _handleCloseTab(TabData tab) async {
    final appState = context.read<AppState>();
    if (!tab.isDirty) {
      appState.closeTab(tab.id);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đóng tab?'),
        content: Text(
            '"${tab.name}" có thay đổi chưa lưu. Đóng tab sẽ mất các thay đổi này.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đóng')),
        ],
      ),
    );
    if (confirmed == true) appState.closeTab(tab.id);
  }

  void _saveCurrentTab() {
    final appState = context.read<AppState>();
    final tab = appState.currentTab;
    if (tab == null) return;
    appState.saveTab(tab.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã lưu "${tab.name}"'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _renameTabDialog(TabData tab) async {
    final controller = TextEditingController(text: tab.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên file',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (newName != null &&
        newName.trim().isNotEmpty &&
        newName.trim() != tab.name) {
      if (!mounted) return;
      context.read<AppState>().renameTab(tab.id, newName.trim());
    }
  }

  Future<void> _editGoModDialog(TabData tab) async {
    final appState = context.read<AppState>();
    final controller = TextEditingController();

    // Nếu tab đã có go.mod → hiển thị nguyên trạng.
    // Nếu chưa có → sinh skeleton từ import ngoài trong code.
    if (tab.goMod != null) {
      controller.text = tab.goMod!;
    } else {
      final external = appState.detectExternalImports(tab.code);
      controller.text = appState.generateGoModSkeleton(external);
    }

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined),
            SizedBox(width: 8),
            Text('go.mod'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Để trống nếu code chỉ dùng stdlib. Backend sẽ tự chạy '
                '`go mod tidy` để resolve version cụ thể.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 12,
                minLines: 8,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'module godroid/main\n\ngo 1.21\n',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          if (tab.goMod != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Xóa go.mod'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null) {
      appState.setGoMod(tab.id, result);
    }
  }

  Future<void> _shareCode() async {
    final tab = context.read<AppState>().currentTab;
    if (tab == null) return;
    try {
      final dir = await getTemporaryDirectory();
      // Share code dưới dạng file .go; nếu có go.mod, share kèm
      // dưới dạng text thuần (share_plus không gộp nhiều file vào một
      // archive được nếu không cài thêm package).
      final file = File('${dir.path}/${tab.name}');
      await file.writeAsString(tab.code);

      if (tab.goMod != null && tab.goMod!.isNotEmpty) {
        final goModFile = File('${dir.path}/go.mod');
        await goModFile.writeAsString(tab.goMod!);
        await Share.shareXFiles(
          [XFile(file.path), XFile(goModFile.path)],
          subject: tab.name,
        );
      } else {
        await Share.shareXFiles([XFile(file.path)], subject: tab.name);
      }
    } catch (e) {
      await Share.share(tab.code, subject: tab.name);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    // Cho phép import cặp (main.go + go.mod) cùng lúc.
    String? goContent;
    String? goModContent;
    String? goName;

    for (final picked in result.files) {
      final ext = picked.extension?.toLowerCase() ?? '';
      final name = picked.name.toLowerCase();

      String? text;
      try {
        if (picked.bytes != null) {
          text = utf8.decode(picked.bytes!);
        } else if (picked.path != null) {
          text = await File(picked.path!).readAsString();
        }
      } catch (_) {
        text = null;
      }
      if (text == null) continue;

      if (name == 'go.mod' || ext == 'mod') {
        goModContent = text;
      } else if (ext == 'go' || ext == 'txt') {
        if (goContent == null) {
          goContent = text;
          goName = picked.name;
        }
      }
    }

    if (goContent == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa chọn file .go hoặc .txt')),
      );
      return;
    }

    final appState = context.read<AppState>();
    appState.importFile(goName!, goContent, goMod: goModContent);

    if (!mounted) return;
    final msg = goModContent != null
        ? 'Đã import "$goName" + go.mod'
        : 'Đã import "$goName"';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _promptAI() async {
    final prompt = await showDialog<String>(
      context: context,
      builder: (_) => AIDialog(),
    );
    if (prompt != null && prompt.isNotEmpty) {
      _generateCode(prompt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    if (!appState.isLoaded) return const _LoadingScreen();

    final currentTab = appState.currentTab;

    // Cảnh báo: code có import ngoài nhưng chưa khai báo go.mod.
    final needsGoMod = currentTab != null &&
        currentTab.goMod == null &&
        appState.detectExternalImports(currentTab.code).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Go Droid'),
            if (currentTab?.isDirty ?? false) ...[
              const SizedBox(width: 8),
              Icon(Icons.circle, size: 8, color: theme.colorScheme.tertiary),
            ],
          ],
        ),
        elevation: 0,
        actions: [
          if (needsGoMod)
            IconButton(
              icon: Icon(
                Icons.warning_amber,
                color: theme.colorScheme.tertiary,
              ),
              tooltip: 'Code cần go.mod — bấm để tạo',
              onPressed: () => _editGoModDialog(currentTab),
            ),
          if (currentTab?.goMod != null)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Đang dùng go.mod — bấm để chỉnh',
              onPressed: () => _editGoModDialog(currentTab!),
            ),
          IconButton(
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            tooltip: _isGenerating ? 'Đang tạo code...' : 'AI Generate',
            onPressed: _isBusy ? null : _promptAI,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Lưu',
            onPressed: (currentTab != null && currentTab.isDirty && !_isBusy)
                ? _saveCurrentTab
                : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Thêm',
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _importFile();
                  break;
                case 'share':
                  _shareCode();
                  break;
                case 'rename':
                  if (currentTab != null) _renameTabDialog(currentTab);
                  break;
                case 'gomod':
                  if (currentTab != null) _editGoModDialog(currentTab);
                  break;
                case 'settings':
                  _showUrlDialog();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Import file (.go/.txt/go.mod)'),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined),
                  title: Text('Chia sẻ code'),
                ),
              ),
              PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Đổi tên file'),
                ),
              ),
              PopupMenuItem(
                value: 'gomod',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Chỉnh go.mod'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Cài đặt backend'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const tabBarHeight = 44.0;
          const statusBarHeight = 32.0;
          const minEditorHeight = 120.0;
          const minOutputHeight = 80.0;

          final available =
              constraints.maxHeight - tabBarHeight - statusBarHeight;
          final maxOutput = available - minEditorHeight;
          final minOutput = minOutputHeight;
          final outputHeight =
              (available * _outputFraction).clamp(minOutput, maxOutput);
          final editorHeight = available - outputHeight;

          return Column(
            children: [
              SizedBox(
                height: tabBarHeight,
                child: _buildTabBar(theme, appState),
              ),
              SizedBox(
                height: editorHeight,
                child: currentTab != null
                    ? CodeEditor(
                        key: ValueKey(currentTab.id),
                        code: currentTab.code,
                        fontSize: appState.editorFontSize,
                        wrap: appState.wordWrap,
                        cursorNotifier: _cursor,
                        onChanged: (newCode) {
                          appState.updateCode(currentTab.id, newCode);
                        },
                      )
                    : const Center(child: Text('Không có tab nào')),
              ),
              SizedBox(
                height: statusBarHeight,
                child: _buildStatusBar(theme, appState, available),
              ),
              SizedBox(
                height: outputHeight,
                child: OutputPanel(
                  result: _result,
                  isRunning: _isRunning,
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (currentTab == null || _isBusy) ? null : _runCode,
        icon: _isRunning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.play_arrow),
        label: Text(_isRunning ? 'Đang chạy' : 'Run'),
        backgroundColor: (currentTab == null || _isBusy)
            ? theme.disabledColor
            : Colors.green.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme, AppState appState) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              itemCount: appState.tabs.length,
              itemBuilder: (ctx, index) {
                final tab = appState.tabs[index];
                final isActive = tab.id == appState.currentTabId;
                return GestureDetector(
                  onTap: () => appState.setCurrentTab(tab.id),
                  onLongPress: () => _renameTabDialog(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: isActive
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            tab.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (tab.goMod != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 11,
                            color: isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.outline,
                          ),
                        ],
                        if (tab.isDirty) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.circle,
                              size: 7, color: theme.colorScheme.tertiary),
                        ],
                        if (appState.tabs.length > 1) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _handleCloseTab(tab),
                            child: Icon(
                              Icons.close,
                              size: 15,
                              color: isActive
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Tab mới',
            visualDensity: VisualDensity.compact,
            onPressed: () => appState.addNewTab(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
      ThemeData theme, AppState appState, double available) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        setState(() {
          final delta = details.delta.dy / available;
          _outputFraction = (_outputFraction - delta).clamp(0.15, 0.75);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_handle,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              ValueListenableBuilder<EditorPosition?>(
                valueListenable: _cursor,
                builder: (_, pos, __) => Text(
                  pos == null
                      ? 'Ln 1, Col 1'
                      : 'Ln ${pos.line}, Col ${pos.column}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
              _SmallIconBtn(
                icon: Icons.text_decrease,
                tooltip: 'Giảm cỡ chữ',
                onPressed: appState.editorFontSize <= 10
                    ? null
                    : () =>
                        appState.setEditorFontSize(appState.editorFontSize - 1),
              ),
              Text(
                appState.editorFontSize.toInt().toString(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              _SmallIconBtn(
                icon: Icons.text_increase,
                tooltip: 'Tăng cỡ chữ',
                onPressed: appState.editorFontSize >= 28
                    ? null
                    : () =>
                        appState.setEditorFontSize(appState.editorFontSize + 1),
              ),
              const SizedBox(width: 4),
              _SmallIconBtn(
                icon: Icons.wrap_text,
                tooltip:
                    appState.wordWrap ? 'Tắt word wrap' : 'Bật word wrap',
                active: appState.wordWrap,
                onPressed: () => appState.setWordWrap(!appState.wordWrap),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUrlDialog() {
    final appState = context.read<AppState>();
    final controller = TextEditingController(text: appState.backendUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'URL',
            border: OutlineInputBorder(),
            hintText: 'http://10.0.2.2:8080',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              appState.setBackendUrl(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const _SmallIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: active ? theme.colorScheme.primary : null,
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Go Droid', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}