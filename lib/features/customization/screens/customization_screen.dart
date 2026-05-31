// lib/features/customization/screens/customization_screen.dart
//
// Premium customization page — pick background from bundled assets
// or upload from device. Selection persists across launches.

import 'dart:convert';
import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/widgets/feature_lock.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  List<String> _assetBackgrounds = [];
  String?      _selected;
  bool         _loading = true;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _selected = LocalDB.getBackgroundImage();
    _loadAssets();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Discover all images in assets/backgrounds/ at runtime ─────────────────
  Future<void> _loadAssets() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = jsonDecode(manifestJson);
      final imageRx = RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false);
      final assets = manifest.keys
          .where((k) => k.startsWith('assets/backgrounds/'))
          .where((k) => imageRx.hasMatch(k))
          .toList()
        ..sort();
      if (mounted) setState(() { _assetBackgrounds = assets; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectAsset(String path) async {
    await LocalDB.setBackgroundImage(path);
    if (mounted) setState(() => _selected = path);
    _snack('Background updated ✓');
  }

  Future<void> _uploadFromDevice() async {
    final picker = ImagePicker();
    final xFile  = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 1920);
    if (xFile == null) return;
    final dir  = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(xFile.path).copy(dest);
    await LocalDB.setBackgroundImage(dest);
    if (mounted) setState(() => _selected = dest);
    _snack('Background uploaded and set ✓');
  }

  Future<void> _resetToDefault() async {
    await LocalDB.clearBackgroundImage();
    if (mounted) setState(() => _selected = null);
    _snack('Reset to default gradient');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!RewardsEntitlements.isUnlocked(RewardFeature.customization)) {
      return FeatureLockScreen(
        featureKey: RewardFeature.customization,
        onUnlocked: () => setState(() {}),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildPreview()),
          SliverToBoxAdapter(child: _buildActions()),
          SliverToBoxAdapter(child: _buildSection('FROM REPO')),
          _buildAssetGrid(),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppTheme.bgDark,
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textSecondary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Customize',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w700)),
      centerTitle: false,
    );
  }

  // ── Live preview ───────────────────────────────────────────────────────────
  Widget _buildPreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PREVIEW',
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: 9 / 12,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.divider),
              boxShadow: AppTheme.cardShadow,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(children: [
              Positioned.fill(child: _renderBackground(_selected)),
              // Dark gradient overlay (matches home screen)
              Positioned.fill(child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xB007101E), Color(0x6007101E), Color(0xDD07101E)],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              )),
              // Mock home content
              Positioned(left: 16, top: 30, child: ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: Text('NOVA X', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w800, letterSpacing: 2)),
              )),
              Positioned(
                left: 16, right: 16, bottom: 30,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x44FFFFFF)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    const Icon(Icons.search, color: AppTheme.accentCyan, size: 14),
                    const SizedBox(width: 8),
                    Text('Search…', style: GoogleFonts.inter(
                        color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Renders the chosen background (asset / file / gradient default)
  Widget _renderBackground(String? path) {
    if (path == null || path.isEmpty) {
      return Container(decoration: const BoxDecoration(gradient: AppTheme.bgGradient));
    }
    if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(gradient: AppTheme.bgGradient)));
    }
    return Image.file(File(path), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient)));
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: _actionCard(
          Icons.upload_rounded, 'Upload',
          'From device', AppTheme.accentCyan, _uploadFromDevice)),
        const SizedBox(width: 12),
        Expanded(child: _actionCard(
          Icons.restart_alt_rounded, 'Reset',
          'Default gradient', AppTheme.warning, _resetToDefault)),
      ]),
    );
  }

  Widget _actionCard(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.18), color.withOpacity(0.05)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(subtitle, style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10)),
          ])),
        ]),
      ),
    );
  }

  // ── Section header ─────────────────────────────────────────────────────────
  Widget _buildSection(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
    child: Text(label, style: GoogleFonts.inter(
        color: AppTheme.textHint, fontSize: 10,
        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  // ── Asset grid ─────────────────────────────────────────────────────────────
  Widget _buildAssetGrid() {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2)),
        ),
      );
    }

    if (_assetBackgrounds.isEmpty) {
      return SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(children: [
            const Icon(Icons.image_outlined, color: AppTheme.textHint, size: 40),
            const SizedBox(height: 12),
            Text('No bundled backgrounds yet',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Add image files (.jpg, .png) to:\nassets/backgrounds/ in your repo.\nThey will appear here automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 11, height: 1.5)),
          ]),
        ),
      ));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 9 / 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _bgTile(_assetBackgrounds[i]),
          childCount: _assetBackgrounds.length,
        ),
      ),
    );
  }

  Widget _bgTile(String assetPath) {
    final active = _selected == assetPath;
    return GestureDetector(
      onTap: () => _selectAsset(assetPath),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? AppTheme.accentCyan : AppTheme.divider,
              width: active ? 2.5 : 1),
          boxShadow: active
              ? [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.4),
                  blurRadius: 14, spreadRadius: 1)]
              : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          Positioned.fill(child: Image.asset(
            assetPath, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                color: AppTheme.bgCard,
                child: const Center(child: Icon(
                    Icons.broken_image_outlined,
                    color: AppTheme.textHint, size: 22))),
          )),
          if (active)
            Positioned(top: 6, right: 6, child: Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(
                color: AppTheme.accentCyan, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            )),
        ]),
      ),
    );
  }
}
