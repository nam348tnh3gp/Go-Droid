import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/code_editor.dart';
import '../widgets/output_panel.dart';
import '../models/app_state.dart';
import '../models/run_result.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EditorScreen extends StatefulWidget {
  @override
  _EditorScreenState createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  String _code = '''
package main

import "fmt"

func main() {
    fmt.Println("Hello, Go!")
}
''';
  RunResult? _result;
  bool _isRunning = false;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = context.read<AppState>().backendUrl;
  }

  Future<void> _runCode() async {
    setState(() {
      _isRunning = true;
      _result = null;
    });

    final appState = context.read<AppState>();
    final url = _urlController.text.trim();
    if (url != appState.backendUrl) {
      appState.backendUrl = url;
    }

    try {
      final response = await http.post(
        Uri.parse('$url/run'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': _code}),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Go Editor'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _showUrlDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: 'Backend URL',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _runCode,
                  icon: _isRunning
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.play_arrow),
                  label: Text(_isRunning ? 'Running...' : 'Run'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: CodeEditor(
              code: _code,
              onChanged: (newCode) => _code = newCode,
            ),
          ),
          Expanded(
            flex: 1,
            child: OutputPanel(result: _result),
          ),
        ],
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