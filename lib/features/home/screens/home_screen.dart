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
  late int bgIndex;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    bgIndex = Random().nextInt(10) + 1;
  }

  void _submitSearch(String query) {
    if (query.trim().isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BrowserView(initialQuery: query)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://api.browser.t-lyfe.com.ng/images/background$bgIndex.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(color: AppTheme.darkBackground),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('NOVA X', style: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.psychology, color: AppTheme.accentCyan, size: 30),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AiAssistantScreen())),
                      )
                    ],
                  ),
                  const SizedBox(height: 60),
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
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Search or type web address',
                            hintStyle: GoogleFonts.inter(color: Colors.white54),
                            icon: const Icon(Icons.search, color: AppTheme.accentCyan),
                          ),
                        ),
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
