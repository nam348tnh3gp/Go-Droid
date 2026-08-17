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

  bool get _isBusy => _isRunning || _isGenerating;

  /// AI models often wrap generated code in a markdown fence, e.g.:
  /// ```go
  /// package main
  /// ...
  /// ```
  /// This strips that fence (and a leading language tag like "Go", "go",
  /// "golang") so only the raw code lands in the new tab.
  String _stripCodeFence(String raw) {
    var text = raw.trim();
    final fenceMatch = RegExp(
      r'^```[ \t]*[a-zA-Z]*[ \t]*\r?\n([\s\S]*?)\r?\n?```[ \t]*$',
    ).firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1) ?? text;
    } else {
      // Fallback: strip stray leading/trailing fence lines even if the
      // overall shape doesn't match (e.g. missing closing fence).
      text = text.replaceFirst(RegExp(r'^```[ \t]*[a-zA-Z]*[ \t]*\r?\n'), '');
      text = text.replaceFirst(RegExp(r'\r?\n?```[ \t]*$'), '');
    }
    return text.trim();
  }

  Future<void> _runCode() async {
    final appState = context.read<AppState>();
    final currentTab = appState.currentTab;
    if (currentTab == null) return;

    setState(() {
      _isRunning = true;
      // UX FIX: previous result stays on screen (dimmed by the spinner in
      // the panel header) instead of flashing back to the empty state.
    });

    final url = appState.backendUrl;

    try {
      final response = await http.post(
        Uri.parse('$url/run'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': currentTab.code}),
      );

      final data = jsonDecode(response.body);
      setState(() {
        _result = RunResult.fromJson(data, response.statusCode == 200);
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _result = RunResult(error: 'Không thể kết nối đến backend: $e', success: false);
        _isRunning = false;
      });
    }
  }

  Future<void> _generateCode(String prompt) async {
    final appState = context.read<AppState>();
    final url = appState.backendUrl;

    setState(() {
      _isGenerating = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$url/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['code'] != null) {
        final generatedCode = _stripCodeFence(data['code'] as String);
        appState.addNewTab(
          name: 'generated_${DateTime.now().millisecondsSinceEpoch}.go',
          code: generatedCode,
        );
        if (!mounted) return;
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
      setState(() {
        _result = RunResult(error: 'Lỗi kết nối: $e', success: false);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _handleCloseTab(TabData tab) async {
    final appState = context.read<AppState>();
    if (!tab.isDirty) {
      appState.closeTab(tab.id);
      return;
    }
    // UX FIX: closing a tab with unsaved changes used to silently discard
    // them. Now we confirm first.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đóng tab?'),
        content: Text('"${tab.name}" có thay đổi chưa lưu. Đóng tab sẽ mất các thay đổi này.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      appState.closeTab(tab.id);
    }
  }

  void _saveCurrentTab() {
    final appState = context.read<AppState>();
    final tab = appState.currentTab;
    if (tab == null) return;
    appState.saveTab(tab.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã lưu "${tab.name}"'), duration: const Duration(seconds: 1)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty && newName.trim() != tab.name) {
      context.read<AppState>().renameTab(tab.id, newName.trim());
    }
  }

  Future<void> _shareCode() async {
    final tab = context.read<AppState>().currentTab;
    if (tab == null) return;
    try {
      // Ghi ra file tạm rồi share dưới dạng file thật (.go) thay vì chỉ
      // share đoạn text thô, để người nhận có thể lưu/mở file đúng định dạng.
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${tab.name}');
      await file.writeAsString(tab.code);
      await Share.shareXFiles([XFile(file.path)], subject: tab.name);
    } catch (e) {
      // Nếu không ghi được file tạm (hiếm), fallback sang share text thuần.
      await Share.share(tab.code, subject: tab.name);
    }
  }

  Future<void> _importFile() async {
    // BUG FIX: FileType.custom filters by MIME type on Android under the
    // hood, and ".go" has no registered MIME type on the OS — so the
    // system picker greyed those files out (only .txt worked, since
    // text/plain is a known MIME type). Using FileType.any avoids the
    // OS-level filter entirely; we validate the extension ourselves after
    // the user picks, which is the approach the file_picker docs recommend
    // for uncommon extensions.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    final ext = picked.extension?.toLowerCase() ?? '';
    if (ext != 'go' && ext != 'txt') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ hỗ trợ import file .go hoặc .txt')),
      );
      return;
    }

    String? content;
    try {
      if (picked.bytes != null) {
        content = utf8.decode(picked.bytes!);
      } else if (picked.path != null) {
        content = await File(picked.path!).readAsString();
      }
    } catch (_) {
      content = null;
    }

    if (!mounted) return;
    if (content == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể đọc file đã chọn')),
      );
      return;
    }

    context.read<AppState>().importFile(picked.name, content);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã import "${picked.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    // Chờ khôi phục các tab đã lưu trước khi vẽ UI, để không bị "nháy"
    // tab mặc định rồi mới thay bằng dữ liệu thật.
    if (!appState.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentTab = appState.currentTab;

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
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI Generate',
            onPressed: _isBusy
                ? null
                : () async {
                    final prompt = await showDialog<String>(
                      context: context,
                      builder: (_) => AIDialog(),
                    );
                    if (prompt != null && prompt.isNotEmpty) {
                      _generateCode(prompt);
                    }
                  },
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
                case 'settings':
                  _showUrlDialog();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Import file'),
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined),
                  title: Text('Chia sẻ code'),
                ),
              ),
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Đổi tên file'),
                ),
              ),
              const PopupMenuItem(
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
      body: Column(
        children: [
          // Tab bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: isActive ? theme.colorScheme.primaryContainer : Colors.transparent,
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
                                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (tab.isDirty) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.circle, size: 7, color: theme.colorScheme.tertiary),
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
          ),
          // Code editor
          Expanded(
            flex: 3,
            child: currentTab != null
                ? CodeEditor(
                    key: ValueKey(currentTab.id),
                    code: currentTab.code,
                    onChanged: (newCode) {
                      appState.updateCode(currentTab.id, newCode);
                    },
                  )
                : const Center(child: Text('Không có tab nào')),
          ),
          // Output panel
          Expanded(
            flex: 2,
            child: OutputPanel(result: _result, isRunning: _isRunning),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (currentTab == null || _isBusy) ? null : _runCode,
        icon: _isRunning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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