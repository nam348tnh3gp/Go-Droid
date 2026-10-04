import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import 'code_editor.dart';

class EditorStatusBar extends StatelessWidget {
  final ValueNotifier<EditorPosition?> cursor;
  final double available;
  final double outputFraction;
  final ValueChanged<double> onOutputFractionChange;

  const EditorStatusBar({
    required this.cursor,
    required this.available,
    required this.outputFraction,
    required this.onOutputFractionChange,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final tab = appState.currentTab;

    // Đếm char/word 1 lần mỗi rebuild (không phải mỗi ký tự gõ).
    int chars = 0;
    int words = 0;
    if (tab != null) {
      final code = tab.code;
      chars = code.length;
      words = code.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        final delta = details.delta.dy / available;
        onOutputFractionChange((outputFraction - delta).clamp(0.15, 0.75));
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.drag_handle,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              ValueListenableBuilder<EditorPosition?>(
                valueListenable: cursor,
                builder: (_, pos, __) => Text(
                  pos == null
                      ? 'Ln 1, Col 1'
                      : 'Ln ${pos.line}, Col ${pos.column}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$chars ký tự · $words từ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              _SmallIconBtn(
                icon: Icons.text_decrease,
                tooltip: 'Giảm cỡ chữ',
                onPressed: appState.editorFontSize <= 10
                    ? null
                    : () => appState
                        .setEditorFontSize(appState.editorFontSize - 1),
              ),
              Text(
                appState.editorFontSize.toInt().toString(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              _SmallIconBtn(
                icon: Icons.text_increase,
                tooltip: 'Tăng cỡ chữ',
                onPressed: appState.editorFontSize >= 28
                    ? null
                    : () => appState
                        .setEditorFontSize(appState.editorFontSize + 1),
              ),
              const SizedBox(width: 4),
              _SmallIconBtn(
                icon: Icons.wrap_text,
                tooltip:
                    appState.wordWrap ? 'Tắt word wrap' : 'Bật word wrap',
                active: appState.wordWrap,
                onPressed: () => appState.setWordWrap(!appState.wordWrap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const _SmallIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: active ? theme.colorScheme.primary : null,
    );
  }
}