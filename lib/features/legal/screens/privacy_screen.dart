// lib/features/legal/screens/privacy_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
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
        Positioned(top: -120, left: -100, child: Container(
          width: 350, height: 350,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentPurple.withOpacity(0.07), Colors.transparent])),
        )),

        CustomScrollView(controller: _scroll, slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
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
                    color: AppTheme.accentPurple, size: 20),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(
                      text: 'NOVA X Privacy Policy — https://t-lyfe.com.ng'));
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
                      AppTheme.accentPurple.withOpacity(0.18),
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
                          color: AppTheme.accentPurple.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.accentPurple.withOpacity(0.3)),
                        ),
                        child: Text('Legal Document',
                            style: GoogleFonts.inter(
                                color: AppTheme.accentPurple, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 10),
                      Text('Privacy\nPolicy',
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

          SliverToBoxAdapter(child: LinearProgressIndicator(
            value: _progress, minHeight: 2,
            color: AppTheme.accentPurple,
            backgroundColor: AppTheme.divider,
          )),

          // ── Content ──────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 60),
            sliver: SliverList(delegate: SliverChildListDelegate([

              _infoCard(
                icon: Icons.privacy_tip_outlined,
                color: AppTheme.accentPurple,
                text: 'At Tech Lyfe Team, we take your privacy seriously. This '
                    'Privacy Policy explains how NOVA X collects, uses, stores, '
                    'and protects your personal information. We are committed to '
                    'being transparent about our data practices.',
              ),
              const SizedBox(height: 24),

              // Data summary chips
              _dataSummaryRow(),
              const SizedBox(height: 24),

              _tocCard([
                '1.  Information We Collect',
                '2.  How We Use Your Data',
                '3.  Data Storage & Security',
                '4.  Third-Party Services',
                '5.  Cookies & Tracking',
                '6.  Push Notifications',
                '7.  Business Directory Data',
                '8.  Children\'s Privacy',
                '9.  Your Rights & Choices',
                '10. Data Retention',
                '11. International Transfers',
                '12. Changes to This Policy',
                '13. Contact Us',
              ]),
              const SizedBox(height: 32),

              _section('1.  Information We Collect',
                  Icons.data_usage_rounded, AppTheme.accentCyan, [
                _sub('Account Information',
                    'When you register, we collect your username, email address, '
                    'and hashed password. We also store your selected avatar color '
                    'and profile preferences.'),
                _sub('Browsing Activity',
                    'With your consent, we store your browsing history, bookmarks, '
                    'and search queries locally on your device and optionally synced '
                    'to our servers for cross-device access. Incognito browsing is '
                    'never stored or synced.'),
                _sub('Business Listings',
                    'If you submit a business listing, we collect the business name, '
                    'description, category, location, website URL, and any images '
                    'you upload.'),
                _sub('Device Information',
                    'We collect your device\'s push notification token (FCM) to '
                    'deliver notifications. We do not collect device IDs, IMEI, '
                    'or hardware fingerprints.'),
                _sub('Usage Analytics',
                    'We collect anonymized usage statistics such as feature usage '
                    'frequency to improve the app experience. This data cannot be '
                    'used to identify you personally.'),
              ]),

              _section('2.  How We Use Your Data',
                  Icons.psychology_outlined, AppTheme.accentPurple, [
                _sub('Service Delivery',
                    'To provide core app functionality: account management, '
                    'bookmark/history sync, business directory, and AI features.'),
                _sub('Push Notifications',
                    'To send you browser alerts, new business notifications, and '
                    'scheduled reminders. You can opt out at any time in '
                    'Settings → Notifications.'),
                _sub('Security & Fraud Prevention',
                    'To detect and prevent unauthorized access, spam, and '
                    'fraudulent business listings.'),
                _sub('Product Improvement',
                    'Anonymized, aggregated data helps us understand which '
                    'features are most useful and identify areas for improvement.'),
                _sub('Legal Compliance',
                    'We may process your data when required by law, court order, '
                    'or other legal process.'),
              ]),

              _section('3.  Data Storage & Security',
                  Icons.lock_outline_rounded, AppTheme.success, [
                _sub('Server Infrastructure',
                    'User data is stored on secured servers hosted in Nigeria '
                    '(DirectAdmin/LiteSpeed). We use TLS/SSL encryption for all '
                    'data transmission.'),
                _sub('Password Security',
                    'Passwords are hashed using bcrypt with a cost factor of 12. '
                    'We never store plaintext passwords.'),
                _sub('Saved Passwords Feature',
                    'Passwords saved by NOVA X\'s password manager are stored '
                    'exclusively on your device using Android\'s encrypted '
                    'SharedPreferences. They are never transmitted to our servers.'),
                _sub('Local Data',
                    'Browsing history, bookmarks, and searches are stored locally '
                    'on your device using secure local storage. You can delete '
                    'this data at any time in Settings.'),
                _sub('Breach Notification',
                    'In the event of a data breach affecting your personal '
                    'information, we will notify affected users within 72 hours '
                    'via email and push notification.'),
              ]),

              _section('4.  Third-Party Services',
                  Icons.extension_outlined, AppTheme.warning, [
                _sub('Firebase (Google)',
                    'We use Firebase Cloud Messaging (FCM) for push notifications. '
                    'Firebase may collect device tokens and notification delivery '
                    'data. Google\'s Privacy Policy applies.'),
                _sub('BRAINS JET AI',
                    'The AI assistant feature sends your queries to external AI '
                    'APIs (including OpenRouter). Do not share sensitive personal '
                    'information in AI conversations.'),
                _sub('Image Generation',
                    'The /image command sends prompts to Pollinations.ai for '
                    'image generation. Pollinations.ai\'s privacy policy applies '
                    'to generated image data.'),
                _sub('SMTP Email Service',
                    'We use our own email server to send verification codes and '
                    'account notifications. Email addresses are used solely for '
                    'this purpose.'),
              ]),

              _section('5.  Cookies & Tracking',
                  Icons.cookie_outlined, AppTheme.accentCyan, [
                _sub('Browser Cookies',
                    'NOVA X\'s built-in browser handles cookies as any standard '
                    'web browser would. Cookies set by websites you visit are '
                    'governed by those websites\' own privacy policies.'),
                _sub('App Analytics',
                    'NOVA X itself does not use advertising cookies or cross-site '
                    'tracking. The Ad Blocker feature actively blocks known '
                    'tracking domains to protect your privacy.'),
                _sub('Cookie Management',
                    'You can view, edit, and delete cookies for any website using '
                    'the built-in Cookie Editor (browser ⋮ menu → Cookie Editor). '
                    'You can also clear all cookies in Settings.'),
              ]),

              _section('6.  Push Notifications',
                  Icons.notifications_outlined, AppTheme.accentPurple, [
                _sub('What We Send',
                    'We send notifications for: new business listings, scheduled '
                    'daily reminders (morning, afternoon, evening), weekly digests, '
                    'and admin broadcasts.'),
                _sub('Opt Out',
                    'You can disable push notifications at any time in your device '
                    'Settings → Apps → NOVA X → Notifications, or by contacting us.'),
                _sub('No Targeted Advertising',
                    'NOVA X does not use push notifications for advertising or '
                    'third-party promotional content. We do not sell notification '
                    'access to advertisers.'),
              ]),

              _section('7.  Business Directory Data',
                  Icons.business_outlined, AppTheme.success, [
                _sub('Public Information',
                    'Business listings are public and visible to all NOVA X users. '
                    'Do not include private personal information in business listings.'),
                _sub('Analytics',
                    'We track search count and visit count per business listing to '
                    'help business owners understand their visibility. This data '
                    'is shown in your profile dashboard.'),
                _sub('Deletion',
                    'You can delete your business listings at any time. Upon '
                    'deletion, the listing and associated images are permanently '
                    'removed from our servers.'),
              ]),

              _section('8.  Children\'s Privacy',
                  Icons.child_care_rounded, AppTheme.warning, [
                _sub('Age Requirement',
                    'NOVA X is not directed at children under 13 years of age. '
                    'We do not knowingly collect personal information from children '
                    'under 13.'),
                _sub('Parental Action',
                    'If you believe your child has provided us with personal '
                    'information without your consent, please contact us '
                    'immediately. We will promptly delete such information.'),
              ]),

              _section('9.  Your Rights & Choices',
                  Icons.manage_accounts_outlined, AppTheme.accentCyan, [
                _sub('Access & Portability',
                    'You can request a copy of all personal data we hold about you '
                    'by contacting us at emmanuelkgyasiarthur@gmail.com.'),
                _sub('Correction',
                    'You can update your profile information at any time in '
                    'Settings → Profile.'),
                _sub('Deletion',
                    'You can delete your account and all associated data by '
                    'contacting us. Account deletion is permanent and irreversible.'),
                _sub('Opt-Out of Communications',
                    'You can opt out of push notifications and marketing emails '
                    'at any time through app settings or by contacting us.'),
                _sub('Data Portability',
                    'We provide your data in standard formats upon request. '
                    'Response time: within 30 days.'),
              ]),

              _section('10. Data Retention',
                  Icons.timer_outlined, AppTheme.accentPurple, [
                _sub('Active Accounts',
                    'We retain your data for as long as your account is active or '
                    'as needed to provide the Service.'),
                _sub('Deleted Accounts',
                    'After account deletion, we delete your personal data within '
                    '30 days, except where retention is required by law.'),
                _sub('Local Data',
                    'Data stored on your device (history, bookmarks, saved '
                    'passwords) remains until you clear it or uninstall the app.'),
              ]),

              _section('11. International Transfers',
                  Icons.language_rounded, AppTheme.success, [
                _sub('Data Location',
                    'Our servers are located in Nigeria. If you access NOVA X from '
                    'outside Nigeria, your data may be transferred to and processed '
                    'in Nigeria. By using the Service, you consent to this transfer.'),
                _sub('Third-Party Transfers',
                    'Third-party services (Firebase, AI APIs) may process data in '
                    'the United States or other countries. These providers comply '
                    'with applicable data protection regulations.'),
              ]),

              _section('12. Changes to This Policy',
                  Icons.update_rounded, AppTheme.warning, [
                _sub('Notification of Changes',
                    'We will notify you of material changes to this Privacy Policy '
                    'via push notification and by updating the "Effective Date" at '
                    'the top of this page.'),
                _sub('Continued Use',
                    'Your continued use of NOVA X after changes are effective '
                    'constitutes your acceptance of the updated Privacy Policy.'),
              ]),

              _contactCard(),
            ])),
          ),
        ]),
      ]),
    );
  }

  Widget _dataSummaryRow() => Row(children: [
    _dataChip('🔒', 'Encrypted', AppTheme.success),
    const SizedBox(width: 8),
    _dataChip('🚫', 'No Ads', AppTheme.accentCyan),
    const SizedBox(width: 8),
    _dataChip('🛡️', 'No Tracking', AppTheme.accentPurple),
  ]);

  Widget _dataChip(String emoji, String label, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      ));

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
            color: AppTheme.accentPurple, fontSize: 13)),
      )),
    ]),
  );

  Widget _section(String title, IconData icon, Color color,
      List<Widget> children) =>
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
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
                border: Border(bottom: BorderSide(color: AppTheme.divider)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 18)),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w800))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ]),
        ),
      );

  Widget _sub(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.inter(
          color: AppTheme.textPrimary, fontSize: 13,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(body, style: GoogleFonts.inter(
          color: AppTheme.textSecondary, fontSize: 13, height: 1.7)),
    ]),
  );

  Widget _contactCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.accentPurple.withOpacity(0.12),
          AppTheme.accentCyan.withOpacity(0.08),
        ],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.accentPurple.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.contact_support_outlined,
              color: Colors.white, size: 20)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('13. Contact Us', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 16,
              fontWeight: FontWeight.w800)),
          Text('Privacy inquiries & data requests',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
        ]),
      ]),
      const SizedBox(height: 16),
      Text('For privacy inquiries, data access requests, or to report a '
          'privacy concern, please contact us:',
          style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
      const SizedBox(height: 16),
      _contactRow(Icons.business_rounded, 'Company', 'Tech Lyfe Team'),
      _contactRow(Icons.person_outline_rounded, 'Developer',
          'Kobby (Mr. Romantic)'),
      _contactRow(Icons.email_outlined, 'Email',
          'emmanuelkgyasiarthur@gmail.com'),
      _contactRow(Icons.chat_outlined, 'WhatsApp', '+233 540 964 040'),
      _contactRow(Icons.chat_outlined, 'WhatsApp', '+233 502 733 366'),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.accentPurple.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accentPurple.withOpacity(0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.timer_outlined,
              color: AppTheme.accentPurple, size: 14),
          const SizedBox(width: 8),
          Text('Data requests fulfilled within 30 days  '
              '•  Breach notifications within 72 hours',
              style: GoogleFonts.inter(
                  color: AppTheme.accentPurple, fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    ]),
  );

  Widget _contactRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(icon, color: AppTheme.accentPurple, size: 16),
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
