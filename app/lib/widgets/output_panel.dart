import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/run_result.dart';

class OutputPanel extends StatelessWidget {
  final RunResult? result;
  final bool isRunning;

  const OutputPanel({this.result, this.isRunning = false, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copyText = result == null
        ? null
        : (result!.success ? result!.output : result!.error);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar: label the panel and offer a copy action.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  'Output',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
                ),
                const Spacer(),
                if (isRunning)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (!isRunning && copyText != null && copyText.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: copyText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildBody(context, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (result == null) {
      return Center(
        child: Text(
          isRunning ? 'Đang chạy code...' : 'Chạy code để xem kết quả',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result!.success) ...[
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade400),
                const SizedBox(width: 6),
                Text('Thành công',
                    style: TextStyle(color: Colors.green.shade400, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              (result!.output?.isNotEmpty ?? false) ? result!.output! : '(không có output)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.error, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text('Lỗi',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              result!.error ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.4,
                color: theme.colorScheme.error,
              ),
            ),
            if (result!.gemini != null && result!.gemini!.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.blueAccent),
                  const SizedBox(width: 6),
                  const Text('Gemini gợi ý',
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                result!.gemini!,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
