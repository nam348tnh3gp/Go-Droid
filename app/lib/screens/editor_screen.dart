import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/run_result.dart';
import '../models/tab_data.dart';
import '../widgets/code_editor.dart';
import '../widgets/editor_tab_bar.dart';
import '../widgets/editor_status_bar.dart';
import '../widgets/editor_search_bar.dart';
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
  bool _isFormatting = false;
  bool _isSearchOpen = false;

  double _outputFraction = 0.38;

  final ValueNotifier<EditorPosition?> _cursor =
      ValueNotifier<EditorPosition?>(null);

  /// Controller hiện tại của CodeEditor. EditorScreen không tạo trực tiếp
  /// mà để CodeEditor báo ra qua `controllerNotifier`. Search bar đọc
  /// notifier này.
  final ValueNotifier<CodeController?> _activeController =
      ValueNotifier<CodeController?>(null);

  bool get _isBusy => _isRunning || _isGenerating || _isFormatting;

  @override
  void dispose() {
    _cursor.dispose();
    _activeController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

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
        _result = RunResult(
            error: 'Không thể kết nối đến backend: $e', success: false);
        _isRunning = false;
      });
    }
  }

  Future<void> _formatCode() async {
    final appState = context.read<AppState>();
    final currentTab = appState.currentTab;
    if (currentTab == null) return;

    setState(() => _isFormatting = true);
    final url = appState.backendUrl;

    try {
      final response = await http.post(
        Uri.parse('$url/format'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': currentTab.code}),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && data['code'] is String) {
        final formatted = data['code'] as String;
        appState.replaceCode(currentTab.id, formatted);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Đã format code'),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        final err = data['error']?.toString() ?? 'Format thất bại';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi format: $err'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi kết nối: $e')),
      );
    } finally {
      if (mounted) setState(() => _isFormatting = false);
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
        final goMod = data['goMod'] is String &&
                (data['goMod'] as String).trim().isNotEmpty
            ? data['goMod'] as String
            : null;

        appState.addNewTab(
          name: 'generated_${DateTime.now().millisecondsSinceEpoch}.go',
          code: generatedCode,
          goMod: goMod,
        );

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

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    if (!appState.isLoaded) return const _LoadingScreen();

    final currentTab = appState.currentTab;
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
              icon: Icon(Icons.warning_amber,
                  color: theme.colorScheme.tertiary),
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
            icon: const Icon(Icons.search),
            tooltip: 'Tìm & thay thế',
            onPressed: (currentTab == null)
                ? null
                : () => setState(() => _isSearchOpen = !_isSearchOpen),
          ),
          IconButton(
            icon: _isFormatting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            tooltip: _isFormatting ? 'Đang format...' : 'Format code (gofmt)',
            onPressed: (currentTab == null || _isBusy) ? null : _formatCode,
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
            onPressed:
                (currentTab != null && currentTab.isDirty && !_isBusy)
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
          final outputHeight =
              (available * _outputFraction).clamp(minOutputHeight, maxOutput);
          final editorHeight = available - outputHeight;

          return Column(
            children: [
              SizedBox(
                height: tabBarHeight,
                child: EditorTabBar(
                  onClose: _handleCloseTab,
                  onRename: _renameTabDialog,
                ),
              ),
              // Search bar — chỉ hiện khi có controller (tránh race khi
              // vừa đổi tab và controller chưa kịp init).
              ValueListenableBuilder<CodeController?>(
                valueListenable: _activeController,
                builder: (_, controller, __) {
                  if (!_isSearchOpen || controller == null) {
                    return const SizedBox.shrink();
                  }
                  return EditorSearchBar(
                    controller: controller,
                    onClose: () => setState(() => _isSearchOpen = false),
                  );
                },
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
                        controllerNotifier: _activeController,
                        onChanged: (newCode) {
                          appState.updateCode(currentTab.id, newCode);
                        },
                      )
                    : const Center(child: Text('Không có tab nào')),
              ),
              SizedBox(
                height: statusBarHeight,
                child: EditorStatusBar(
                  cursor: _cursor,
                  available: available,
                  outputFraction: _outputFraction,
                  onOutputFractionChange: (v) =>
                      setState(() => _outputFraction = v),
                ),
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