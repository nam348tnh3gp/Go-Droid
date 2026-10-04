import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/go.dart';

/// Vị trí con trỏ (1-based) để hiển thị trên status bar.
class EditorPosition {
  final int line;
  final int column;
  const EditorPosition(this.line, this.column);
}

class CodeEditor extends StatefulWidget {
  final String code;
  final ValueChanged<String> onChanged;
  final double fontSize;
  final bool wrap;
  final ValueNotifier<EditorPosition?>? cursorNotifier;

  const CodeEditor({
    required this.code,
    required this.onChanged,
    this.fontSize = 14,
    this.wrap = true,
    this.cursorNotifier,
    Key? key,
  }) : super(key: key);

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(text: widget.code, language: go);
    _controller.addListener(_handleChange);
    // Báo vị trí ban đầu sau frame đầu tiên.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportCursor());
  }

  void _handleChange() {
    widget.onChanged(_controller.text);
    _reportCursor();
  }

  void _reportCursor() {
    final notifier = widget.cursorNotifier;
    if (notifier == null) return;
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    final offset = sel.baseOffset.clamp(0, text.length);
    final before = text.substring(0, offset);
    final line = '\n'.allMatches(before).length + 1;
    final lastNewline = before.lastIndexOf('\n');
    final col = offset - lastNewline;
    notifier.value = EditorPosition(line, col);
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Khi bật/tắt wrap hoặc đổi font-size ta không cần đụng controller.
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
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: CodeField(
          controller: _controller,
          minLines: null,
          wrap: widget.wrap,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: widget.fontSize,
            height: 1.45,
          ),
          padding: const EdgeInsets.all(12),
          lineNumberStyle: LineNumberStyle(
            margin: 12,
            width: 36,
            textStyle: TextStyle(color: theme.colorScheme.outline),
          ),
          cursorColor: theme.colorScheme.primary,
          background: theme.colorScheme.surfaceContainerLow,
        ),
      ),
    );
  }
}