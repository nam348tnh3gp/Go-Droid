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

  /// Khi widget mount, state sẽ set notifier này về controller của nó.
  /// Khi unmount, reset về null (nếu vẫn đang giữ controller đó).
  /// Dùng để widget khác (search bar) truy cập controller an toàn.
  final ValueNotifier<CodeController?>? controllerNotifier;

  const CodeEditor({
    required this.code,
    required this.onChanged,
    this.fontSize = 14,
    this.wrap = true,
    this.cursorNotifier,
    this.controllerNotifier,
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

    // Sync controller ra ngoài. Set sync ở đây an toàn vì widget con
    // chưa build xong — listeners chỉ schedule rebuild cho frame sau.
    widget.controllerNotifier?.value = _controller;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportCursor();
    });
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Phát hiện code bị thay đổi từ BÊN NGOÀI (Format, tab switch giữ
    // nguyên widget). Nếu user gõ, _controller.text đã == widget.code
    // rồi, nên check này không trigger.
    if (widget.code != _controller.text) {
      final sel = _controller.selection;
      _controller.removeListener(_handleChange);
      _controller.text = widget.code;
      _controller.addListener(_handleChange);

      // Giữ con trỏ trong bounds mới.
      if (sel.isValid) {
        final max = widget.code.length;
        _controller.selection = TextSelection(
          baseOffset: sel.baseOffset.clamp(0, max),
          extentOffset: sel.extentOffset.clamp(0, max),
        );
      }
      _reportCursor();
    }

    // Nếu callback đổi (widget mới được reuse), rebind notifier.
    if (oldWidget.controllerNotifier != widget.controllerNotifier) {
      oldWidget.controllerNotifier?.value = null;
      widget.controllerNotifier?.value = _controller;
    }
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
  void dispose() {
    if (widget.controllerNotifier?.value == _controller) {
      widget.controllerNotifier?.value = null;
    }
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