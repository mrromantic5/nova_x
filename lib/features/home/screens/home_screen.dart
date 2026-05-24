import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';
import '../../ai/screens/ai_assistant_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _bgIndex;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Random background 1-10 fetched from the api.browser server
    _bgIndex = Random().nextInt(10) + 1;
  }

  @override
  void dispose() {
    // FIXED: was missing — caused a memory leak each time HomeScreen rebuilt
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _searchController.clear();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrowserView(initialQuery: q)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar — full-screen immersive layout
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Dynamic background image from api.browser server ─────────────
          Image.network(
            'https://api.browser.t-lyfe.com.ng/images/background$_bgIndex.jpg',
            fit: BoxFit.cover,
            // Dark fallback if the server is unreachable
            errorBuilder: (_, __, ___) =>
                Container(color: AppTheme.darkBackground),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(color: AppTheme.darkBackground);
            },
          ),

          // ── Glassmorphic foreground ──────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Header row: logo + title + AI button ─────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            height: 32,
                            width: 32,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.blur_on,
                              color: AppTheme.accentCyan,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'NOVA X',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      // AI assistant shortcut
                      IconButton(
                        icon: const Icon(
                          Icons.psychology,
                          color: AppTheme.accentCyan,
                          size: 30,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AiAssistantScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 60),

                  // ── Glassmorphic search bar ───────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.glassWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: _submitSearch,
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search or type a web address',
                            hintStyle:
                                GoogleFonts.inter(color: Colors.white54),
                            icon: const Icon(
                              Icons.search,
                              color: AppTheme.accentCyan,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.arrow_forward,
                                color: AppTheme.accentCyan,
                              ),
                              onPressed: () =>
                                  _submitSearch(_searchController.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Hint text ─────────────────────────────────────────────
                  Center(
                    child: Text(
                      'Powered by NOVA X Engine',
                      style: GoogleFonts.inter(
                        color: Colors.white30,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
