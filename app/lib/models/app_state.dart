import 'package:flutter/material.dart';
import 'tab_data.dart';

class AppState extends ChangeNotifier {
  List<TabData> _tabs = [];
  String _currentTabId = '';
  String _backendUrl = 'http://10.0.2.2:8080';

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

  AppState() {
    _tabs.add(TabData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'main.go',
      code: defaultCode,
    ));
    _currentTabId = _tabs.first.id;
  }

  // Tạo tên file duy nhất, tránh trùng lặp
  String _getUniqueTabName(String baseName) {
    String nameWithoutExt = baseName;
    String ext = '';
    int dotIndex = baseName.lastIndexOf('.');
    if (dotIndex != -1) {
      nameWithoutExt = baseName.substring(0, dotIndex);
      ext = baseName.substring(dotIndex);
    }
    Set<String> existingNames = _tabs.map((t) => t.name).toSet();
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
  }

  void renameTab(String id, String newName) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    final uniqueName = _getUniqueTabName(newName);
    tab.name = uniqueName;
    notifyListeners();
  }

  void closeTab(String id) {
    if (_tabs.length <= 1) return;
    _tabs.removeWhere((t) => t.id == id);
    if (_currentTabId == id) {
      _currentTabId = _tabs.last.id;
    }
    notifyListeners();
  }

  void setCurrentTab(String id) {
    if (_currentTabId != id && _tabs.any((t) => t.id == id)) {
      _currentTabId = id;
      notifyListeners();
    }
  }

  void updateCode(String id, String newCode) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    tab.code = newCode;
    tab.isDirty = true;
    notifyListeners();
  }

  void setBackendUrl(String url) {
    if (_backendUrl != url) {
      _backendUrl = url;
      notifyListeners();
    }
  }

  void saveTab(String id) {
    final tab = _tabs.firstWhere((t) => t.id == id);
    tab.isDirty = false;
    notifyListeners();
  }

  String getCurrentCode() => currentTab?.code ?? '';
}