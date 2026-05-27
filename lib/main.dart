// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'features/auth/screens/auth_gate.dart';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Background messages are shown automatically by FCM on Android
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await LocalDB.initialize();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: NovaXApp()));
}

class NovaXApp extends StatefulWidget {
  const NovaXApp({super.key});
  @override
  State<NovaXApp> createState() => _NovaXAppState();
}

class _NovaXAppState extends State<NovaXApp> {
  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;

    // Request notification permissions
    await messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    // Get and register FCM token
    final token = await messaging.getToken();
    if (token != null) {
      await ApiService.registerFcmToken(token);
    }

    // Listen for token refreshes
    messaging.onTokenRefresh.listen((newToken) {
      ApiService.registerFcmToken(newToken);
    });

    // Handle notification taps when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // FCM shows heads-up notifications on Android automatically
      // Additional foreground handling can go here
    });
  }

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
