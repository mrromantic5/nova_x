// lib/features/legal/screens/terms_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'privacy_screen.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});
  @override State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final ScrollController _scroll = ScrollController();
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.maxScrollExtent > 0) {
        setState(() => _progress =
            _scroll.offset / _scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        // Background glow
        Positioned(top: -120, right: -100, child: Container(
          width: 350, height: 350,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentCyan.withOpacity(0.07), Colors.transparent])),
        )),

        CustomScrollView(controller: _scroll, slivers: [
          // ── Premium App Bar ─────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.bgDark,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.ios_share_rounded,
                    color: AppTheme.accentCyan, size: 20),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                      text: 'NOVA X Terms of Service — https://t-lyfe.com.ng'));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Link copied!',
                        style: GoogleFonts.inter(color: Colors.white)),
                    backgroundColor: AppTheme.bgElevated,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF07101E),
                      AppTheme.accentCyan.withOpacity(0.15),
                    ],
                  ),
                ),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.accentCyan.withOpacity(0.3)),
                        ),
                        child: Text('Legal Document',
                            style: GoogleFonts.inter(
                                color: AppTheme.accentCyan, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 10),
                      Text('Terms of\nService',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontSize: 32,
                              fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 8),
                      Text('Effective: June 1, 2026  •  v2.6',
                          style: GoogleFonts.inter(
                              color: AppTheme.textHint, fontSize: 12)),
                    ],
                  ),
                )),
              ),
            ),
          ),

          // ── Reading progress bar ─────────────────────────────────────────
          SliverToBoxAdapter(child: LinearProgressIndicator(
            value: _progress, minHeight: 2,
            color: AppTheme.accentCyan,
            backgroundColor: AppTheme.divider,
          )),

          // ── Content ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
            sliver: SliverList(delegate: SliverChildListDelegate([

              // Intro card
              _infoCard(
                icon: Icons.info_outline_rounded,
                color: AppTheme.accentCyan,
                text: 'By downloading, installing, or using NOVA X, you agree to '
                    'be bound by these Terms of Service. Please read them carefully '
                    'before using the application.',
              ),
              const SizedBox(height: 24),

              // TOC
              _tocCard([
                '1.  Acceptance of Terms',
                '2.  Description of Service',
                '3.  User Accounts',
                '4.  Acceptable Use',
                '5.  Business Directory',
                '5b. Built-In Tools & Features',
                '6.  Intellectual Property',
                '7.  Privacy & Data',
                '8.  Disclaimers',
                '9.  Limitation of Liability',
                '10. Termination',
                '11. Changes to Terms',
                '12. Governing Law',
                '13. Contact Us',
              ]),
              const SizedBox(height: 32),

              _section('1.  Acceptance of Terms', Icons.handshake_outlined,
                  AppTheme.accentCyan,
                  'By accessing or using NOVA X ("the App", "the Service"), you '
                  'confirm that you are at least 13 years of age and have the legal '
                  'capacity to enter into these Terms. If you are using the App on '
                  'behalf of an organization, you represent that you have authority '
                  'to bind that organization to these Terms.\n\n'
                  'If you do not agree with any part of these Terms, you must not '
                  'use NOVA X. Continued use of the App after updates to these Terms '
                  'constitutes acceptance of the revised Terms.'),

              _section('2.  Description of Service', Icons.public_rounded,
                  AppTheme.accentPurple,
                  'NOVA X is a mobile web browser application developed by Tech Lyfe '
                  'Team ("we", "us", "our"). The App provides:\n\n'
                  '• Secure web browsing with privacy controls\n'
                  '• Incognito/private browsing mode\n'
                  '• Business directory listing and discovery\n'
                  '• AI-powered assistant (BRAINS JET AI)\n'
                  '• Cloud bookmark and history sync\n'
                  '• Push notifications and alerts\n'
                  '• Password management (encrypted local storage)\n'
                  '• Reader Mode (clean article reading)\n'
                  '• Ad Blocker (blocks 60+ ad and tracker domains)\n'
                  '• Cookie Editor (view, edit and delete browser cookies)\n'
                  '• NOVA Cyber (website security scanning tool)\n'
                  '• Visual Search / Lens (search by image)\n'
                  '• App Shortcuts (quick launch from home screen)\n'
                  '• Developer tools and advanced browser controls\n\n'
                  'We reserve the right to modify, suspend, or discontinue any '
                  'feature of the Service at any time without prior notice.'),

              _section('3.  User Accounts', Icons.person_outline_rounded,
                  AppTheme.success,
                  'To access certain features of NOVA X, you must create an account. '
                  'You agree to:\n\n'
                  '• Provide accurate and complete registration information\n'
                  '• Verify your email address during registration\n'
                  '• Maintain the confidentiality of your password\n'
                  '• Notify us immediately of any unauthorized account access\n'
                  '• Accept responsibility for all activities under your account\n\n'
                  'We reserve the right to suspend or terminate accounts that '
                  'violate these Terms, engage in fraudulent activity, or remain '
                  'inactive for extended periods. You may not create accounts on '
                  'behalf of others without authorization.'),

              _section('4.  Acceptable Use', Icons.shield_outlined,
                  AppTheme.warning,
                  'You agree to use NOVA X only for lawful purposes. You must NOT:\n\n'
                  '• Use the App to access, transmit, or distribute illegal content\n'
                  '• Attempt to reverse-engineer, decompile, or hack the App\n'
                  '• Use automated tools to scrape or abuse the Service\n'
                  '• Impersonate other users, businesses, or Tech Lyfe Team\n'
                  '• Transmit malware, viruses, or malicious code\n'
                  '• Engage in spamming, phishing, or fraudulent activities\n'
                  '• Violate the intellectual property rights of others\n'
                  '• Use the App to stalk, harass, or harm any individual\n'
                  '• Circumvent any security or access control measures\n\n'
                  'Violations may result in immediate account termination and may '
                  'be reported to relevant authorities.'),

              _section('5.  Business Directory', Icons.business_outlined,
                  AppTheme.accentCyan,
                  'NOVA X includes a Business Directory feature allowing users to '
                  'list and discover businesses. By submitting a business listing:\n\n'
                  '• You confirm you are authorized to represent the business\n'
                  '• All information provided is accurate and not misleading\n'
                  '• You grant us a license to display the listing in the App\n'
                  '• You will keep listing information current and accurate\n'
                  '• Maximum of 2 active listings per registered account\n\n'
                  'We reserve the right to review, edit, or remove any listing '
                  'that violates these Terms, contains inappropriate content, or '
                  'is reported by other users as fraudulent or misleading. We do '
                  'not endorse any business listed in the directory.'),

              _section('5b. Built-In Tools & Features', Icons.build_circle_outlined,
                  AppTheme.accentCyan,
                  'NOVA X includes the following advanced built-in tools. By using each tool, '
                  'you agree to use it responsibly and lawfully:\n\n'
                  '• Ad Blocker: Blocks advertising and tracking domains. We do not guarantee '
                  'completeness. Some legitimate content may be affected.\n\n'
                  '• Password Manager: Credentials are stored encrypted on your device only. '
                  'We never transmit saved passwords. You are responsible for device security.\n\n'
                  '• Cookie Editor: Allows viewing and editing browser cookies for any website '
                  'you visit. Use responsibly and only on sites you own or have permission to modify.\n\n'
                  '• Reader Mode: Extracts and reformats article content for easier reading. '
                  'Content remains copyright of the original publisher.\n\n'
                  '• NOVA Cyber (Security Scanner): Performs passive security checks on websites '
                  'including header analysis, SQL injection probing, XSS testing, and file exposure '
                  'scanning. Results are informational only. We make no guarantee of completeness or '
                  'accuracy. You must not use NOVA Cyber to scan websites without authorisation. '
                  'Scanning third-party systems without permission may be illegal in your jurisdiction.\n\n'
                  '• Visual Search: Uploads your selected image to Google Image Search. By using '
                  'this feature, you acknowledge that your image is sent to Google and Google\'s '
                  'Privacy Policy applies to that data.\n\n'
                  '• App Shortcuts: Long-press shortcuts launch specific app screens. These are '
                  'convenience features and do not grant additional permissions.'),

              _section('6.  Intellectual Property', Icons.copyright_rounded,
                  AppTheme.accentPurple,
                  'All content within NOVA X — including the app design, graphics, '
                  'logo, name, branding, source code, and BRAINS JET AI — is the '
                  'exclusive property of Tech Lyfe Team and is protected by '
                  'applicable copyright, trademark, and intellectual property laws.\n\n'
                  'You are granted a limited, non-exclusive, non-transferable, '
                  'revocable license to use NOVA X for personal, non-commercial '
                  'purposes. You may not:\n\n'
                  '• Copy, modify, or distribute the App or its content\n'
                  '• Create derivative works based on NOVA X\n'
                  '• Use NOVA X branding without written permission\n'
                  '• Sublicense or sell access to the Service'),

              _section('7.  Privacy & Data', Icons.lock_outline_rounded,
                  AppTheme.success,
                  'Your use of NOVA X is also governed by our Privacy Policy, '
                  'which is incorporated into these Terms by reference. By using '
                  'the App, you consent to the collection and use of information '
                  'as described in our Privacy Policy.\n\n'
                  'We implement industry-standard security measures to protect '
                  'your data, but no transmission over the internet is 100% '
                  'secure. You use the Service at your own risk.'),

              _section('8.  Disclaimers', Icons.warning_amber_rounded,
                  AppTheme.warning,
                  'NOVA X IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT '
                  'WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED.\n\n'
                  'We do not warrant that:\n\n'
                  '• The Service will be uninterrupted or error-free\n'
                  '• Defects will be corrected in a timely manner\n'
                  '• The Service is free from viruses or harmful components\n'
                  '• Any information obtained via the App is accurate\n\n'
                  'We are not responsible for any third-party websites accessed '
                  'through NOVA X\'s browser functionality. Access to third-party '
                  'content is at your own risk.'),

              _section('9.  Limitation of Liability', Icons.gavel_rounded,
                  AppTheme.danger,
                  'TO THE MAXIMUM EXTENT PERMITTED BY LAW, TECH LYFE TEAM SHALL '
                  'NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, '
                  'CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, '
                  'REVENUE, DATA, OR GOODWILL.\n\n'
                  'Our total liability to you for any claims arising from your '
                  'use of NOVA X shall not exceed the amount you paid (if any) '
                  'for using the Service in the twelve months preceding the claim.\n\n'
                  'Some jurisdictions do not allow the exclusion of certain '
                  'warranties or limitation of liability, so some of the above '
                  'limitations may not apply to you.'),

              _section('10. Termination', Icons.cancel_outlined,
                  AppTheme.textHint,
                  'Either party may terminate these Terms at any time. You may '
                  'delete your account at any time through the app settings.\n\n'
                  'We may terminate or suspend your access immediately, without '
                  'prior notice, if you breach these Terms, engage in fraudulent '
                  'or illegal activity, or if we discontinue the Service.\n\n'
                  'Upon termination, your right to use NOVA X ceases immediately. '
                  'We may retain certain data as required by law or for legitimate '
                  'business purposes, as outlined in our Privacy Policy.'),

              _section('11. Changes to Terms', Icons.update_rounded,
                  AppTheme.accentCyan,
                  'We may update these Terms from time to time to reflect changes '
                  'in our practices, legal requirements, or features. When we make '
                  'material changes, we will:\n\n'
                  '• Send a push notification to registered users\n'
                  '• Update the "Last Updated" date at the top of this page\n'
                  '• Require re-acceptance if changes are significant\n\n'
                  'Your continued use of NOVA X after any changes constitute '
                  'your acceptance of the updated Terms.'),

              _section('12. Governing Law', Icons.account_balance_outlined,
                  AppTheme.accentPurple,
                  'These Terms shall be governed by and construed in accordance '
                  'with the laws of the Republic of Ghana, without regard to its '
                  'conflict of law provisions.\n\n'
                  'Any disputes arising from these Terms or your use of NOVA X '
                  'shall be resolved through binding arbitration or in the courts '
                  'of competent jurisdiction in Ghana. You agree to submit to the '
                  'personal jurisdiction of such courts.'),

              // Contact card
              _contactCard(context),

              const SizedBox(height: 24),

              // Privacy Policy link
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const PrivacyScreen())),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(children: [
                    const Icon(Icons.privacy_tip_outlined,
                        color: AppTheme.accentCyan, size: 22),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Privacy Policy', style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.textPrimary, fontSize: 15,
                          fontWeight: FontWeight.w700)),
                      Text('How we collect and protect your data',
                          style: GoogleFonts.inter(
                              color: AppTheme.textHint, fontSize: 12)),
                    ])),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: AppTheme.textHint, size: 14),
                  ]),
                ),
              ),
            ])),
          ),
        ]),
      ]),
    );
  }

  Widget _infoCard({required IconData icon, required Color color,
      required String text}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.6))),
        ]),
      );

  Widget _tocCard(List<String> items) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Table of Contents', style: GoogleFonts.spaceGrotesk(
          color: AppTheme.textPrimary, fontSize: 14,
          fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(item, style: GoogleFonts.inter(
            color: AppTheme.accentCyan, fontSize: 13)),
      )),
    ]),
  );

  Widget _section(String title, IconData icon, Color color, String body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Section header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
                border: Border(
                    bottom: BorderSide(color: AppTheme.divider)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w800))),
              ]),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(body, style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 13.5,
                  height: 1.75)),
            ),
          ]),
        ),
      );

  Widget _contactCard(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.accentCyan.withOpacity(0.12),
          AppTheme.accentPurple.withOpacity(0.08),
        ],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.support_agent_rounded,
              color: Colors.white, size: 20)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('13. Contact Us', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 16,
              fontWeight: FontWeight.w800)),
          Text('We\'re here to help',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
        ]),
      ]),
      const SizedBox(height: 16),
      Text('For questions, concerns, or legal inquiries about these Terms:',
          style: GoogleFonts.inter(color: AppTheme.textSecondary,
              fontSize: 13, height: 1.6)),
      const SizedBox(height: 16),
      _contactRow(Icons.business_rounded, 'Company', 'Tech Lyfe Team'),
      _contactRow(Icons.email_outlined, 'Email',
          'emmanuelkgyasiarthur@gmail.com'),
      _contactRow(Icons.chat_outlined, 'WhatsApp', '+233 540 964 040'),
      _contactRow(Icons.chat_outlined, 'WhatsApp', '+233 502 733 366'),
      const SizedBox(height: 12),
      Text('Response time: within 48 business hours',
          style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 11)),
    ]),
  );

  Widget _contactRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, color: AppTheme.accentCyan, size: 16),
      const SizedBox(width: 10),
      Text('$label: ', style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 13,
          fontWeight: FontWeight.w600)),
      Expanded(child: Text(value, style: GoogleFonts.inter(
          color: AppTheme.textPrimary, fontSize: 13,
          fontWeight: FontWeight.w600))),
    ]),
  );
}
