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
import 'features/business/screens/business_screen.dart';
import 'features/browser/screens/browser_view.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Channel that reads which shortcut the user tapped from MainActivity.kt
const _shortcutChannel = MethodChannel('com.example.nova_x/shortcuts');

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await LocalDB.initialize();
  await Firebase.initializeApp();
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
    _initShortcuts();
  }

  // ── App Shortcuts (long-press home screen icon) ────────────────────────────
  // Reads the action sent by MainActivity.kt when a shortcut was tapped,
  // then navigates to the correct screen after the widget tree is ready.
  Future<void> _initShortcuts() async {
    try {
      // Small delay so AuthGate/HomeScreen finishes mounting first
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;

      final action = await _shortcutChannel.invokeMethod<String>('getShortcut') ?? '';
      if (action.isEmpty) return;

      final nav = navigatorKey.currentState;
      if (nav == null) return;

      switch (action) {
        case 'com.example.nova_x.NEW_TAB':
          // Open browser to Google (blank new tab)
          nav.push(MaterialPageRoute(
              builder: (_) => const BrowserView(initialQuery: 'https://www.google.com')));
          break;
        case 'com.example.nova_x.PRIVATE_TAB':
          // Open incognito browser session
          nav.push(MaterialPageRoute(
              builder: (_) => const BrowserView(
                  initialQuery: 'https://www.google.com', incognito: true)));
          break;
        case 'com.example.nova_x.BUSINESS':
          // Open the business directory
          nav.push(MaterialPageRoute(builder: (_) => const BusinessScreen()));
          break;
      }
    } catch (_) {
      // Shortcut channel not available (e.g. first install before MainActivity.kt deployed)
    }
  }

  // ── FCM Push Notifications ─────────────────────────────────────────────────
  Future<void> _initFCM() async {
    final msg = FirebaseMessaging.instance;

    await msg.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    await msg.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    final token = await msg.getToken();
    if (token != null) await ApiService.registerFcmToken(token);
    msg.onTokenRefresh.listen((t) => ApiService.registerFcmToken(t));

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      if (notif == null) return;
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(notif.title ?? '',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            if ((notif.body ?? '').isNotEmpty)
              Text(notif.body ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF111827),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'View',
          textColor: const Color(0xFF00D4FF),
          onPressed: () => _handleMessage(message),
        ),
      ));
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    final initial = await msg.getInitialMessage();
    if (initial != null) {
      await Future.delayed(const Duration(milliseconds: 800));
      _handleMessage(initial);
    }
  }

  void _handleMessage(RemoteMessage message) {
    final data   = message.data;
    final screen = data['screen'] ?? 'home';
    final url    = data['url']    ?? '';
    final nav    = navigatorKey.currentState;
    if (nav == null) return;

    if (screen == 'business') {
      nav.push(MaterialPageRoute(builder: (_) => const BusinessScreen()));
    } else if (screen == 'url' && url.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => BrowserView(initialQuery: url)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'NOVA X',
      debugShowCheckedModeBanner: false,
      navigatorKey:             navigatorKey,
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
