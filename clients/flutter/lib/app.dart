import 'package:flutter/material.dart';

import 'features/connection/connection_screen.dart';
import 'features/media/persistent_mini_player.dart';

class HomeServerApp extends StatelessWidget {
  const HomeServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeServer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF536DFE)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const ConnectionScreen(),
      builder: (context, child) => Column(
        children: [
          Expanded(child: child ?? const SizedBox.shrink()),
          const PersistentMiniPlayer(),
        ],
      ),
    );
  }
}
