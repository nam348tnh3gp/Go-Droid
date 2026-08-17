import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tab_data.dart';

class AppState extends ChangeNotifier {
  List<TabData> _tabs = [];
  String _currentTabId = '';
  String _backendUrl = 'http://10.0.2.2:8080';

  // UI reads this to show a loading state until saved tabs are restored,
  // so we never briefly flash a blank/default tab on top of real data.
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

  Timer? _debounce;

  AppState() {
    _tabs.add(TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'main.go',
      code: defaultCode,
    ));
    _currentTabId = _tabs.first.id;
    _restoreState();
  }

  // Khôi phục các tab đã lưu từ lần dùng trước, nếu có. Nếu không tìm thấy
  // hoặc dữ liệu lỗi, giữ nguyên tab mặc định đã tạo ở constructor.
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
          _currentTabId = (savedCurrent != null && _tabs.any((t) => t.id == savedCurrent))
              ? savedCurrent
              : _tabs.first.id;
        }
      }
      final savedUrl = prefs.getString(_prefsBackendUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        _backendUrl = savedUrl;
      }
    } catch (_) {
      // Dữ liệu lưu trước đó bị hỏng/không đọc được -> bỏ qua, dùng mặc định.
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
    } catch (_) {
      // Lưu thất bại không nên làm crash app; dữ liệu vẫn còn trong bộ nhớ.
    }
  }

  // Gõ code sẽ gọi hàm này rất thường xuyên -> gộp (debounce) các lần ghi
  // xuống đĩa để tránh ghi liên tục theo từng ký tự.
  void _schedulePersist() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _persist);
  }

  // Tạo tên file duy nhất, tránh trùng lặp. [ignoreId] dùng khi đổi tên để
  // không tự so trùng với chính tab đang đổi tên.
  String _getUniqueTabName(String baseName, {String? ignoreId}) {
    String nameWithoutExt = baseName;
    String ext = '';
    int dotIndex = baseName.lastIndexOf('.');
    if (dotIndex != -1) {
      nameWithoutExt = baseName.substring(0, dotIndex);
      ext = baseName.substring(dotIndex);
    }
    Set<String> existingNames = _tabs
        .where((t) => t.id != ignoreId)
        .map((t) => t.name)
        .toSet();
    if (!existingNames.contains(baseName)) {
      return baseName;
    }
    int counter = 1;
    while (true) {
      String newName = '$nameWithoutExt$counter$ext';
      if (!existingNames.contains(newName)) {
        return newName;
      }
      counter++;
    }
  }

  void addNewTab({String? name, String? code}) {
    final defaultName = 'untitled.go';
    final finalName = name != null ? _getUniqueTabName(name) : _getUniqueTabName(defaultName);
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: finalName,
      code: code ?? defaultCode,
    );
    _tabs.add(newTab);
    _currentTabId = newTab.id;
    notifyListeners();
    _persist();
  }

  // Tạo tab mới từ nội dung file được import từ máy, giữ tên file gốc
  // (chỉ đổi nếu trùng với tab đang mở).
  void importFile(String fileName, String content) {
    final uniqueName = _getUniqueTabName(fileName);
    final newTab = TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: uniqueName,
      code: content,
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

  void updateCode(String id, String newCode) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    if (tab.code == newCode) return;
    tab.code = newCode;
    tab.isDirty = true;
    notifyListeners();
    _schedulePersist();
  }

  void setBackendUrl(String url) {
    if (_backendUrl != url) {
      _backendUrl = url;
      notifyListeners();
      _persist();
    }
  }

  // Lưu tường minh (người dùng bấm nút Save): xóa cờ "chưa lưu" và ghi
  // ngay xuống bộ nhớ máy (không chờ debounce).
  void saveTab(String id) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    tab.isDirty = false;
    notifyListeners();
    _debounce?.cancel();
    _persist();
  }

  String getCurrentCode() => currentTab?.code ?? '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
