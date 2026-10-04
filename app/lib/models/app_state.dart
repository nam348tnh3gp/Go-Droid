import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tab_data.dart';

class AppState extends ChangeNotifier {
  // ... (giữ nguyên phần khai báo cũ)

  List<TabData> _tabs = [];
  String _currentTabId = '';
  String _backendUrl = 'http://10.0.2.2:8080';
  double _editorFontSize = 14.0;
  bool _wordWrap = true;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  List<TabData> get tabs => _tabs;
  String get currentTabId => _currentTabId;
  TabData? get currentTab {
    try {
      return _tabs.firstWhere((t) => t.id == _currentTabId);
    } catch (_) {
      return _tabs.isNotEmpty ? _tabs.first : null;
    }
  }
  String get backendUrl => _backendUrl;
  double get editorFontSize => _editorFontSize;
  bool get wordWrap => _wordWrap;

  static const String defaultCode = '''
package main

import "fmt"

func main() {
    fmt.Println("Hello, Go!")
}
''';

  static const _prefsTabsKey = 'go_droid_tabs';
  static const _prefsCurrentTabKey = 'go_droid_current_tab';
  static const _prefsBackendUrlKey = 'go_droid_backend_url';
  static const _prefsFontSizeKey = 'go_droid_font_size';
  static const _prefsWordWrapKey = 'go_droid_word_wrap';

  Timer? _persistDebounce;

  AppState() {
    _tabs.add(TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'main.go',
      code: defaultCode,
    ));
    _currentTabId = _tabs.first.id;
    _restoreState();
  }

  // ... (_restoreState, _persist, _schedulePersist, _getUniqueTabName
  //      giữ NGUYÊN như file hiện tại)

  // ============ Tab operations ============

  void addNewTab({String? name, String? code, String? goMod}) {
    final defaultName = 'untitled.go';
    final finalName =
        name != null ? _getUniqueTabName(name) : _getUniqueTabName(defaultName);
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: finalName,
      code: code ?? defaultCode,
      goMod: goMod,
    );
    _tabs.add(newTab);
    _currentTabId = newTab.id;
    notifyListeners();
    _persist();
  }

  void importFile(String fileName, String content, {String? goMod}) {
    final uniqueName = _getUniqueTabName(fileName);
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: uniqueName,
      code: content,
      goMod: goMod,
    );
    _tabs.add(newTab);
    _currentTabId = newTab.id;
    notifyListeners();
    _persist();
  }

  void renameTab(String id, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final tab = _tabs.firstWhere((t) => t.id == id);
    final uniqueName = _getUniqueTabName(trimmed, ignoreId: id);
    if (uniqueName == tab.name) return;
    tab.name = uniqueName;
    notifyListeners();
    _persist();
  }

  void closeTab(String id) {
    if (_tabs.length <= 1) return;
    _tabs.removeWhere((t) => t.id == id);
    if (_currentTabId == id) {
      _currentTabId = _tabs.last.id;
    }
    notifyListeners();
    _persist();
  }

  /// Nhân bản tab (code + goMod), đặt ngay sau tab gốc.
  void duplicateTab(String id) {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final src = _tabs[idx];
    final newName = _getUniqueTabName(src.name);
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: newName,
      code: src.code,
      goMod: src.goMod,
    );
    _tabs.insert(idx + 1, newTab);
    _currentTabId = newTab.id;
    notifyListeners();
    _persist();
  }

  /// Đóng tất cả tab khác, giữ lại đúng tab [keepId].
  void closeOtherTabs(String keepId) {
    if (_tabs.length <= 1) return;
    _tabs.removeWhere((t) => t.id != keepId);
    _currentTabId = keepId;
    notifyListeners();
    _persist();
  }

  /// Đóng hết, tạo 1 tab mặc định mới.
  void closeAllTabs() {
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'main.go',
      code: defaultCode,
    );
    _tabs = [newTab];
    _currentTabId = newTab.id;
    notifyListeners();
    _persist();
  }

  void setCurrentTab(String id) {
    if (_currentTabId != id && _tabs.any((t) => t.id == id)) {
      _currentTabId = id;
      notifyListeners();
      _persist();
    }
  }

  /// PERF: Không notify mỗi ký tự. Chỉ notify khi cờ `isDirty` chuyển
  /// false -> true để tab bar hiện dấu chấm.
  void updateCode(String id, String newCode) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    if (tab.code == newCode) return;
    final wasDirty = tab.isDirty;
    tab.code = newCode;
    tab.isDirty = true;
    if (!wasDirty) notifyListeners();
    _schedulePersist();
  }

  /// Thay thế toàn bộ code của tab (dùng cho Format / Replace all).
  /// Luôn notify để editor sync controller.
  void replaceCode(String id, String newCode) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    if (tab.code == newCode) return;
    tab.code = newCode;
    tab.isDirty = true;
    notifyListeners();
    _persist();
  }

  void saveTab(String id) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    tab.isDirty = false;
    notifyListeners();
    _persistDebounce?.cancel();
    _persist();
  }

  // ============ Settings ============

  void setBackendUrl(String url) {
    if (_backendUrl != url) {
      _backendUrl = url;
      notifyListeners();
      _persist();
    }
  }

  void setEditorFontSize(double size) {
    final clamped = size.clamp(10.0, 28.0);
    if (_editorFontSize != clamped) {
      _editorFontSize = clamped;
      notifyListeners();
      _schedulePersist();
    }
  }

  void setWordWrap(bool value) {
    if (_wordWrap != value) {
      _wordWrap = value;
      notifyListeners();
      _schedulePersist();
    }
  }

  // ============ go.mod support (giữ nguyên đợt trước) ============

  void setGoMod(String id, String? content) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    final normalized =
        (content == null || content.trim().isEmpty) ? null : content;
    if (tab.goMod == normalized) return;
    tab.goMod = normalized;
    tab.isDirty = true;
    notifyListeners();
    _persistDebounce?.cancel();
    _persist();
  }

  List<String> detectExternalImports(String code) {
    final re = RegExp(
      r'^\s*(?:import\s+)?(?:[\w.]+\s+)?"([^"]+)"',
      multiLine: true,
    );
    final modules = <String>{};
    for (final m in re.allMatches(code)) {
      final path = m.group(1)!;
      if (path.isEmpty) continue;
      final parts = path.split('/');
      if (!parts.first.contains('.')) continue;

      final host = parts.first.toLowerCase();
      if (host.contains('github.com') ||
          host.contains('gitlab.com') ||
          host.contains('bitbucket.org')) {
        if (parts.length >= 3) {
          if (parts.length >= 4 &&
              RegExp(r'^v\d+$').hasMatch(parts[3]) &&
              !parts[2].startsWith('v')) {
            modules.add('${parts[0]}/${parts[1]}/${parts[2]}/${parts[3]}');
          } else {
            modules.add('${parts[0]}/${parts[1]}/${parts[2]}');
          }
        }
      } else if (parts.length >= 2) {
        modules.add('${parts[0]}/${parts[1]}');
      }
    }
    return modules.toList();
  }

  String generateGoModSkeleton(
    List<String> modules, {
    String moduleName = 'godroid/main',
  }) {
    final buf = StringBuffer()
      ..writeln('module $moduleName')
      ..writeln()
      ..writeln('go 1.21');
    if (modules.isNotEmpty) {
      buf.writeln();
      buf.writeln('require (');
      for (final m in modules) {
        buf.writeln('\t$m latest');
      }
      buf.writeln(')');
    }
    return buf.toString();
  }

  String getCurrentCode() => currentTab?.code ?? '';

  @override
  void dispose() {
    _persistDebounce?.cancel();
    super.dispose();
  }
}