import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  String _backendUrl = 'http://10.0.2.2:8080'; // mặc định cho Android emulator

  String get backendUrl => _backendUrl;

  set backendUrl(String url) {
    _backendUrl = url;
    notifyListeners();
  }

  void saveBackendUrl(String url) async {
    // Lưu bằng shared_preferences nếu cần
  }
}