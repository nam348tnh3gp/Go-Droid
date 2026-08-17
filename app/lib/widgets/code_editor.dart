import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/go.dart';

class CodeEditor extends StatelessWidget {
  final String code;
  final ValueChanged<String> onChanged;

  const CodeEditor({required this.code, required this.onChanged, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = CodeController(
      text: code,
      language: go,
    );
    controller.addListener(() {
      onChanged(controller.text);
    });

    return Container(
      margin: EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade700),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CodeField(
          controller: controller,
          wrap: true,
          textStyle: TextStyle(fontFamily: 'monospace', fontSize: 14),
          lineNumberStyle: LineNumberStyle(
            margin: 8,
            textStyle: TextStyle(color: Colors.grey),
          ),
          cursorColor: Colors.cyanAccent, // 👈 hiển thị rõ con trỏ
        ),
      ),
    );
  }
}