import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/run_result.dart';
import '../widgets/code_editor.dart';
import '../widgets/output_panel.dart';
import '../widgets/ai_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EditorScreen extends StatefulWidget {
  @override
  _EditorScreenState createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final TextEditingController _urlController = TextEditingController();
  RunResult? _result;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = context.read<AppState>().backendUrl;
  }

  Future<void> _runCode() async {
    final appState = context.read<AppState>();
    final currentTab = appState.currentTab;
    if (currentTab == null) return;

    setState(() {
      _isRunning = true;
      _result = null;
    });

    final url = _urlController.text.trim();
    if (url != appState.backendUrl) {
      appState.setBackendUrl(url);
    }

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
    final url = _urlController.text.trim();
    if (url != appState.backendUrl) {
      appState.setBackendUrl(url);
    }

    setState(() {
      _isRunning = true;
      _result = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$url/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['code'] != null) {
        final generatedCode = data['code'];
        appState.addNewTab(
          name: 'generated_${DateTime.now().millisecondsSinceEpoch}.go',
          code: generatedCode,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Code đã được tạo trong tab mới!')),
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
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentTab = appState.currentTab;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Go Droid'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _showUrlDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Thanh công cụ
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: 'Backend URL',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.auto_awesome),
                  tooltip: 'AI Generate',
                  onPressed: () async {
                    final prompt = await showDialog<String>(
                      context: context,
                      builder: (_) => AIDialog(),
                    );
                    if (prompt != null && prompt.isNotEmpty) {
                      _generateCode(prompt);
                    }
                  },
                ),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runCode,
                  icon: _isRunning
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.play_arrow),
                  label: Text(_isRunning ? 'Running' : 'Run'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Tab Bar
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: appState.tabs.length,
              itemBuilder: (ctx, index) {
                final tab = appState.tabs[index];
                final isActive = tab.id == appState.currentTabId;
                return GestureDetector(
                  onTap: () => appState.setCurrentTab(tab.id),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    margin: EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isActive ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tab.name,
                          style: TextStyle(
                            color: isActive ? Theme.of(context).colorScheme.onPrimaryContainer : Colors.grey,
                          ),
                        ),
                        if (tab.isDirty) ...[
                          SizedBox(width: 4),
                          Icon(Icons.circle, size: 8, color: Colors.orange),
                        ],
                        if (appState.tabs.length > 1) ...[
                          SizedBox(width: 8),
                          InkWell(
                            onTap: () => appState.closeTab(tab.id),
                            child: Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Code editor
          Expanded(
            flex: 2,
            child: currentTab != null
                ? CodeEditor(
                    key: ValueKey(currentTab.id),
                    code: currentTab.code,
                    onChanged: (newCode) {
                      appState.updateCode(currentTab.id, newCode);
                    },
                  )
                : Center(child: Text('Không có tab nào')),
          ),
          // Output panel
          Expanded(
            flex: 1,
            child: OutputPanel(result: _result),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          appState.addNewTab();
        },
        child: Icon(Icons.add),
        tooltip: 'New Tab',
      ),
    );
  }

  void _showUrlDialog() {
    final controller = TextEditingController(text: _urlController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Backend URL'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _urlController.text = controller.text;
                context.read<AppState>().setBackendUrl(controller.text);
              });
              Navigator.pop(ctx);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}