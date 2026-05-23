import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

/// Root widget. Sets up theming and routes to the [HomeScreen].
class MemeMakerApp extends StatelessWidget {
  const MemeMakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meme Maker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
