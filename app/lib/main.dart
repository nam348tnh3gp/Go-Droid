import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/editor_screen.dart';
import 'models/app_state.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Go Editor',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
        ),
        home: EditorScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}