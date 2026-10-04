import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../models/tab_data.dart';

class EditorTabBar extends StatelessWidget {
  final Future<void> Function(TabData tab) onClose;
  final Future<void> Function(TabData tab) onRename;

  const EditorTabBar({
    required this.onClose,
    required this.onRename,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final tabs = appState.tabs;
    final currentId = appState.currentTabId;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              itemCount: tabs.length,
              itemBuilder: (ctx, index) {
                final tab = tabs[index];
                final isActive = tab.id == currentId;
                return GestureDetector(
                  onTap: () => appState.setCurrentTab(tab.id),
                  onLongPress: () => _showContextMenu(context, tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: isActive
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            tab.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (tab.goMod != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 11,
                            color: isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.outline,
                          ),
                        ],
                        if (tab.isDirty) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.circle,
                              size: 7, color: theme.colorScheme.tertiary),
                        ],
                        if (tabs.length > 1) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onClose(tab),
                            child: Icon(
                              Icons.close,
                              size: 15,
                              color: isActive
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Tab mới',
            visualDensity: VisualDensity.compact,
            onPressed: () => appState.addNewTab(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, TabData tab) async {
    final appState = context.read<AppState>();
    final theme = Theme.of(context);
    final multiTab = appState.tabs.length > 1;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(60, 90, 60, 0),
      items: [
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.drive_file_rename_outline, size: 20),
            title: Text('Đổi tên'),
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_outlined, size: 20),
            title: Text('Nhân bản'),
          ),
        ),
        const PopupMenuItem(
          value: 'copy_name',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link, size: 20),
            title: Text('Copy tên file'),
          ),
        ),
        if (multiTab) const PopupMenuDivider(),
        if (multiTab)
          const PopupMenuItem(
            value: 'close',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.close, size: 20),
              title: Text('Đóng tab'),
            ),
          ),
        if (multiTab)
          const PopupMenuItem(
            value: 'close_others',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.close_fullscreen, size: 20),
              title: Text('Đóng tab khác'),
            ),
          ),
        if (multiTab)
          PopupMenuItem(
            value: 'close_all',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cancel_outlined,
                  size: 20, color: theme.colorScheme.error),
              title: Text('Đóng tất cả',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ),
      ],
    );

    if (result == null || !context.mounted) return;
    switch (result) {
      case 'rename':
        await onRename(tab);
        break;
      case 'duplicate':
        appState.duplicateTab(tab.id);
        break;
      case 'copy_name':
        await Clipboard.setData(ClipboardData(text: tab.name));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã copy "${tab.name}"'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        break;
      case 'close':
        await onClose(tab);
        break;
      case 'close_others':
        appState.closeOtherTabs(tab.id);
        break;
      case 'close_all':
        appState.closeAllTabs();
        break;
    }
  }
}