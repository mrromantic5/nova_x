// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/nova_shield_service.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'features/auth/screens/auth_gate.dart';
import 'features/business/screens/business_screen.dart';
import 'features/browser/screens/browser_view.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  await NovaShieldService.init();
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

  // ── Core fix: poll until navigator is mounted, then navigate ───────────────
  //
  // Root cause of the bug:
  //   navigatorKey.currentState is null when the app is cold-started from a
  //   notification tap because AuthGate runs an async API auth-check before
  //   pushing HomeScreen. This can take 2-5 s — far longer than the old 800 ms
  //   fixed delay. Background taps also occasionally hit a null nav window.
  //
  // Fix: poll every 200 ms for up to 10 s. The instant the navigator mounts
  //   (i.e. AuthGate finishes and HomeScreen is shown) we do the push.
  Future<void> _navigateWhenReady(RemoteMessage message) async {
    const pollInterval = Duration(milliseconds: 200);
    const maxWait      = Duration(seconds: 10);
    final deadline     = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      if (navigatorKey.currentState != null) {
        _doNavigate(message);
        return;
      }
      await Future.delayed(pollInterval);
    }
  }

  // ── Perform the actual screen push based on data payload ───────────────────
  void _doNavigate(RemoteMessage message) {
    final data   = message.data;
    final screen = data['screen'] ?? 'home';
    final url    = data['url']    ?? '';
    final nav    = navigatorKey.currentState;
    if (nav == null) return;

    switch (screen) {
      case 'business':
        nav.push(MaterialPageRoute(
            builder: (_) => const BusinessScreen()));
        break;
      case 'url':
        if (url.isNotEmpty) {
          nav.push(MaterialPageRoute(
              builder: (_) => BrowserView(initialQuery: url)));
        }
        break;
      case 'home':
      default:
        break;
    }
  }

  // ── App Shortcuts (long-press home-screen icon) ────────────────────────────
  Future<void> _initShortcuts() async {
    try {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      final action =
          await _shortcutChannel.invokeMethod<String>('getShortcut') ?? '';
      if (action.isEmpty) return;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      switch (action) {
        case 'com.example.nova_x.NEW_TAB':
          nav.push(MaterialPageRoute(
              builder: (_) =>
                  const BrowserView(initialQuery: 'https://www.google.com')));
          break;
        case 'com.example.nova_x.PRIVATE_TAB':
          nav.push(MaterialPageRoute(
              builder: (_) => const BrowserView(
                  initialQuery: 'https://www.google.com', incognito: true)));
          break;
        case 'com.example.nova_x.BUSINESS':
          nav.push(
              MaterialPageRoute(builder: (_) => const BusinessScreen()));
          break;
      }
    } catch (_) {}
  }

  // ── FCM initialisation ─────────────────────────────────────────────────────
  Future<void> _initFCM() async {
    final msg = FirebaseMessaging.instance;

    await msg.requestPermission(
        alert: true, badge: true, sound: true, provisional: false);
    await msg.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true);

    final token = await msg.getToken();
    if (token != null) await ApiService.registerFcmToken(token);
    msg.onTokenRefresh.listen((t) => ApiService.registerFcmToken(t));

    // FOREGROUND — show snackbar with tap-to-view
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
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF111827),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'View',
          textColor: const Color(0xFF00D4FF),
          onPressed: () => _doNavigate(message),
        ),
      ));
    });

    // BACKGROUND — app in background, user taps notification
    // _navigateWhenReady handles the brief window where nav may be null
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateWhenReady);

    // TERMINATED — app was killed, user taps notification
    // Do NOT use a fixed delay. Poll until AuthGate finishes loading.
    final initial = await msg.getInitialMessage();
    if (initial != null) {
      _navigateWhenReady(initial);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                     'NOVA X',
      debugShowCheckedModeBanner: false,
      navigatorKey:              navigatorKey,
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
