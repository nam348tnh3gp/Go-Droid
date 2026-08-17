import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/go.dart';

class CodeEditor extends StatefulWidget {
  final String code;
  final ValueChanged<String> onChanged;

  const CodeEditor({required this.code, required this.onChanged, Key? key})
      : super(key: key);

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    // BUG FIX: the controller used to be created inside build(), which ran
    // on every keystroke and reset the cursor to the start of the file.
    // It's now created once and kept alive for the lifetime of this tab
    // (the parent passes a ValueKey(tab.id), so switching tabs still
    // creates a fresh instance correctly).
    _controller = CodeController(
      text: widget.code,
      language: go,
    );
    _controller.addListener(_handleChange);
  }

  void _handleChange() {
    widget.onChanged(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CodeField(
        controller: _controller,
        wrap: true,
        textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4),
        padding: const EdgeInsets.all(12),
        lineNumberStyle: LineNumberStyle(
          margin: 12,
          width: 36,
          textStyle: TextStyle(color: theme.colorScheme.outline),
        ),
        cursorColor: theme.colorScheme.primary,
        background: theme.colorScheme.surfaceContainerLow,
      ),
    );
  }
}
