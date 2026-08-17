import 'package:flutter/material.dart';

class AIDialog extends StatefulWidget {
  @override
  _AIDialogState createState() => _AIDialogState();
}

class _AIDialogState extends State<AIDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('AI Generate Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: 'Mô tả code cần tạo',
              border: OutlineInputBorder(),
              hintText: 'VD: Viết hàm tính giai thừa',
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final prompt = _controller.text.trim();
            if (prompt.isNotEmpty) {
              Navigator.pop(context, prompt);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Vui lòng nhập mô tả')),
              );
            }
          },
          child: Text('Generate'),
        ),
      ],
    );
  }
}