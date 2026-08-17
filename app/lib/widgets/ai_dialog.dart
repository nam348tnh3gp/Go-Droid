import 'package:flutter/material.dart';

class AIDialog extends StatefulWidget {
  @override
  _AIDialogState createState() => _AIDialogState();
}

class _AIDialogState extends State<AIDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Autofocus so the keyboard is ready immediately on mobile.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final prompt = _controller.text.trim();
    if (prompt.isNotEmpty) {
      Navigator.pop(context, prompt);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập mô tả')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome),
          SizedBox(width: 8),
          Text('AI Generate Code'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: const InputDecoration(
              labelText: 'Mô tả code cần tạo',
              border: OutlineInputBorder(),
              hintText: 'VD: Viết hàm tính giai thừa',
            ),
            maxLines: 3,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 8),
          Text(
            'Kết quả sẽ được tạo trong một tab mới.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
