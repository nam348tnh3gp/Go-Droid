import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tab_data.dart';

class AppState extends ChangeNotifier {
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

  Future<void> _restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawTabs = prefs.getString(_prefsTabsKey);
      if (rawTabs != null) {
        final decoded = jsonDecode(rawTabs) as List<dynamic>;
        final restored = decoded
            .map((e) => TabData.fromJson(e as Map<String, dynamic>))
            .toList();
        if (restored.isNotEmpty) {
          _tabs = restored;
          final savedCurrent = prefs.getString(_prefsCurrentTabKey);
          _currentTabId =
              (savedCurrent != null && _tabs.any((t) => t.id == savedCurrent))
                  ? savedCurrent
                  : _tabs.first.id;
        }
      }
      final savedUrl = prefs.getString(_prefsBackendUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _backendUrl = savedUrl;
      }
      _editorFontSize = prefs.getDouble(_prefsFontSizeKey) ?? 14.0;
      _wordWrap = prefs.getBool(_prefsWordWrapKey) ?? true;
    } catch (_) {
      // dữ liệu hỏng → dùng mặc định
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawTabs = jsonEncode(_tabs.map((t) => t.toJson()).toList());
      await prefs.setString(_prefsTabsKey, rawTabs);
      await prefs.setString(_prefsCurrentTabKey, _currentTabId);
      await prefs.setString(_prefsBackendUrlKey, _backendUrl);
      await prefs.setDouble(_prefsFontSizeKey, _editorFontSize);
      await prefs.setBool(_prefsWordWrapKey, _wordWrap);
    } catch (_) {
      // lưu thất bại không crash app
    }
  }

  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 600), _persist);
  }

  String _getUniqueTabName(String baseName, {String? ignoreId}) {
    String nameWithoutExt = baseName;
    String ext = '';
    int dotIndex = baseName.lastIndexOf('.');
    if (dotIndex != -1) {
      nameWithoutExt = baseName.substring(0, dotIndex);
      ext = baseName.substring(dotIndex);
    }
    Set<String> existingNames =
        _tabs.where((t) => t.id != ignoreId).map((t) => t.name).toSet();
    if (!existingNames.contains(baseName)) return baseName;
    int counter = 1;
    while (true) {
      String newName = '$nameWithoutExt$counter$ext';
      if (!existingNames.contains(newName)) return newName;
      counter++;
    }
  }

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

  void setCurrentTab(String id) {
    if (_currentTabId != id && _tabs.any((t) => t.id == id)) {
      _currentTabId = id;
      notifyListeners();
      _persist();
    }
  }

  /// PERF: Không notify mỗi ký tự nữa — chỉ notify đúng một lần khi cờ
  /// `isDirty` chuyển false -> true (để tab bar hiện dấu chấm). Bản thân
  /// nội dung code đã nằm trong controller của editor; khi cần (Run/Save/
  /// switch tab) chỉ việc đọc trực tiếp `currentTab.code` là có bản mới
  /// nhất — vì ta mutate thẳng vào object TabData.
  void updateCode(String id, String newCode) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    if (tab.code == newCode) return;
    final wasDirty = tab.isDirty;
    tab.code = newCode;
    tab.isDirty = true;
    if (!wasDirty) notifyListeners();
    _schedulePersist();
  }

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

  void saveTab(String id) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    tab.isDirty = false;
    notifyListeners();
    _persistDebounce?.cancel();
    _persist();
  }

  // ---------------------------------------------------------------
  // go.mod support
  // ---------------------------------------------------------------

  /// Cập nhật go.mod cho tab. `null` hoặc chuỗi rỗng → xoá (về chế độ
  /// single-file, backend sẽ tự tạo skeleton).
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

  /// Phát hiện import package ngoài stdlib từ code (heuristic đơn giản,
  /// không parse AST). Trả về danh sách module path root, ví dụ:
  /// "github.com/google/uuid", "golang.org/x/sync".
  List<String> detectExternalImports(String code) {
    // Bắt mọi dòng có dạng: [import] [alias] "path"
    // (khớp cả import block — mỗi dòng là `    "path"` hoặc `alias "path"`)
    final re = RegExp(
      r'^\s*(?:import\s+)?(?:[\w.]+\s+)?"([^"]+)"',
      multiLine: true,
    );
    final modules = <String>{};
    for (final m in re.allMatches(code)) {
      final path = m.group(1)!;
      if (path.isEmpty) continue;
      final parts = path.split('/');
      // Stdlib: segment đầu không có dấu chấm (fmt, os, net/http...).
      if (!parts.first.contains('.')) continue;

      // Module root heuristic:
      // - github/gitlab/bitbucket: 3 segment
      // - host khác (golang.org, k8s.io...): 2 segment
      final host = parts.first.toLowerCase();
      if (host.contains('github.com') ||
          host.contains('gitlab.com') ||
          host.contains('bitbucket.org')) {
        if (parts.length >= 3) {
          // Xử lý version suffix /vN ở cuối (vd: .../uuid/v2)
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

  /// Sinh nội dung go.mod tối thiểu từ danh sách module. Version để
  /// "latest" — backend sẽ chạy `go mod tidy` để resolve version thật.
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