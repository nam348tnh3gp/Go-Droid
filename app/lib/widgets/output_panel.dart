import 'package:flutter/material.dart';
import '../models/run_result.dart';

class OutputPanel extends StatelessWidget {
  final RunResult? result;

  const OutputPanel({this.result, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: result == null
          ? Center(
              child: Text(
                'Chạy code để xem kết quả',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result!.success) ...[
                    Text('✅ Output:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      result!.output ?? '',
                      style: TextStyle(color: Colors.white, fontFamily: 'monospace'),
                    ),
                  ] else ...[
                    Text('❌ Lỗi:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      result!.error ?? '',
                      style: TextStyle(color: Colors.redAccent, fontFamily: 'monospace'),
                    ),
                    if (result!.gemini != null && result!.gemini!.isNotEmpty) ...[
                      Divider(color: Colors.grey),
                      Text('🤖 Gemini phản hồi:', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text(
                        result!.gemini!,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}