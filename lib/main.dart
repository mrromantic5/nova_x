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

/// Global navigator key — lets us navigate from outside widget tree (FCM handler)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Background message handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // The system will show the notification automatically.
  // Navigation happens when the user TAPS the notification (onMessageOpenedApp).
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
  }

  Future<void> _initFCM() async {
    final msg = FirebaseMessaging.instance;

    // Request permission
    await msg.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );

    // Set foreground notification options (show heads-up on Android)
    await msg.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    // Register FCM token with server
    final token = await msg.getToken();
    if (token != null) await ApiService.registerFcmToken(token);

    // Token refresh
    msg.onTokenRefresh.listen((t) => ApiService.registerFcmToken(t));

    // Foreground message — show in-app snackbar
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

    // Background → app opened by tapping notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    // Terminated → app opened by tapping notification
    final initial = await msg.getInitialMessage();
    if (initial != null) {
      // Delay slightly to ensure the widget tree is ready
      await Future.delayed(const Duration(milliseconds: 800));
      _handleMessage(initial);
    }
  }

  /// Route the user to the correct screen based on notification data payload
  void _handleMessage(RemoteMessage message) {
    final data   = message.data;
    final screen = data['screen'] ?? 'home';
    final url    = data['url']    ?? '';

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (screen == 'business') {
      // Open global business directory
      nav.push(MaterialPageRoute(builder: (_) => const BusinessScreen()));
    } else if (screen == 'url' && url.isNotEmpty) {
      // Open a specific URL in the browser
      nav.push(MaterialPageRoute(
          builder: (_) => BrowserView(initialQuery: url)));
    }
    // screen == 'home' → no navigation, app is already open or at home
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'NOVA X',
      debugShowCheckedModeBanner: false,
      navigatorKey:             navigatorKey, // ← required for push from outside widget tree
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
