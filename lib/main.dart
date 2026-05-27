// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'features/auth/screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await LocalDB.initialize();
  runApp(const ProviderScope(child: NovaXApp()));
}

class NovaXApp extends StatelessWidget {
  const NovaXApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'NOVA X',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3:            true,
        scaffoldBackgroundColor: AppTheme.bgDark,
        colorScheme: ColorScheme.dark(
          primary:   AppTheme.accentCyan,
          secondary: AppTheme.accentPurple,
          surface:   AppTheme.bgCard,
        ),
      ),
      home: const AuthGate(),
    );
  }
}
