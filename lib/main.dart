import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/database/local_db.dart';
import 'features/home/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for consistent browser experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar — content renders behind it
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarIconBrightness:  Brightness.light,
    systemNavigationBarColor: Color(0xFF07101E),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await LocalDB.initialize();

  runApp(
    const ProviderScope(child: NovaXApp()),
  );
}

class NovaXApp extends StatelessWidget {
  const NovaXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'NOVA X',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.darkTheme,
      themeMode:                ThemeMode.dark,
      home:                     const HomeScreen(),
    );
  }
}
