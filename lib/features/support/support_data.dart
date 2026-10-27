// lib/features/support/support_data.dart
//
// 3.9.0 — Help center content: ticket and issue categories and the FAQ.
// Answers marked `askNova` are answered live by NOVA AI (it knows the NOVA X
// feature guide); the others have a written answer.

import 'package:flutter/material.dart';

class SupportCategory {
  const SupportCategory(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

/// Must match nova_platform.php (support tickets).
const supportCategories = [
  SupportCategory('account', 'Account & login', Icons.manage_accounts_rounded),
  SupportCategory('billing', 'Premium & payments', Icons.credit_card_rounded),
  SupportCategory('rewards', 'Rewards & coins', Icons.monetization_on_rounded),
  SupportCategory('nova_ai', 'NOVA AI', Icons.auto_awesome_rounded),
  SupportCategory('voice', 'Hey NOVA & voice', Icons.mic_rounded),
  SupportCategory('browser', 'Browsing', Icons.public_rounded),
  SupportCategory('business', 'NOVA Business', Icons.storefront_rounded),
  SupportCategory('privacy', 'Privacy & data', Icons.privacy_tip_rounded),
  SupportCategory('bug', 'Something is broken', Icons.bug_report_rounded),
  SupportCategory('feedback', 'Ideas & feedback', Icons.lightbulb_rounded),
  SupportCategory('other', 'Other', Icons.help_rounded),
];

/// Must match nova_platform.php (issue reports).
const issueCategories = [
  SupportCategory('crash', 'App crash', Icons.error_rounded),
  SupportCategory('browser', 'Browser', Icons.public_rounded),
  SupportCategory('nova_ai', 'NOVA AI', Icons.auto_awesome_rounded),
  SupportCategory('voice', 'Hey NOVA / voice', Icons.mic_rounded),
  SupportCategory('music', 'NOVA Music', Icons.music_note_rounded),
  SupportCategory('network', 'NOVA Network', Icons.speed_rounded),
  SupportCategory('rewards', 'Rewards', Icons.monetization_on_rounded),
  SupportCategory('business', 'Business', Icons.storefront_rounded),
  SupportCategory('notifications', 'Notifications', Icons.notifications_rounded),
  SupportCategory('ui', 'Design / display', Icons.palette_rounded),
  SupportCategory('performance', 'Slow / battery', Icons.battery_alert_rounded),
  SupportCategory('other', 'Other', Icons.more_horiz_rounded),
];

String supportCategoryLabel(String key) =>
    supportCategories.firstWhere((c) => c.key == key, orElse: () => supportCategories.last).label;

String issueCategoryLabel(String key) =>
    issueCategories.firstWhere((c) => c.key == key, orElse: () => issueCategories.last).label;

class FaqItem {
  const FaqItem(this.question, {this.answer, this.askNova = false});
  final String question;

  /// Written answer (null when NOVA answers live).
  final String? answer;
  final bool askNova;
}

class FaqSection {
  const FaqSection(this.title, this.icon, this.items);
  final String title;
  final IconData icon;
  final List<FaqItem> items;
}

const faqSections = [
  FaqSection('Getting started', Icons.rocket_launch_rounded, [
    FaqItem('How do I make NOVA X my default browser?', askNova: true),
    FaqItem('How do I turn on "Hey NOVA"?', askNova: true),
    FaqItem('Where are my bookmarks, history and downloads?', askNova: true),
    FaqItem('How do I browse privately (incognito)?', askNova: true),
  ]),
  FaqSection('Plans, Premium & payments', Icons.workspace_premium_rounded, [
    FaqItem('What is free and what is Premium?',
        answer: 'Free: the browser, NOVA Shield (malware & phishing blocking, HTTPS upgrade, encrypted DNS), '
            'NOVA AI with daily limits (40 messages, 5 photo uploads and 5 images every 24 hours), '
            'Hey NOVA, NOVA Music and NOVA Network.\n\n'
            'With coins (Rewards → Redeem) you can unlock for a few days: NOVA Shield Pro, Cyber, '
            'Dev Tools, Cookie Editor, Customization, Speed Dial, a Business listing and AI Boost '
            '(double NOVA AI limits for 24 hours).\n\n'
            'NOVA X Premium unlocks everything, plus NOVA Map, AI video generation, 300 NOVA AI '
            'messages / 30 photo uploads / 20 images a day, X Coder saving and a premium badge.'),
    FaqItem('I paid but Premium is not active',
        answer: 'Open Profile → Premium and pull down to refresh. Premium activates as soon as the payment '
            'is confirmed by the payment provider (usually within a minute). If it is still not active '
            'after 15 minutes, open a ticket in the "Premium & payments" category with your payment '
            'reference — we fix these first.'),
    FaqItem('How do I cancel or renew Premium?',
        answer: 'Premium does not renew automatically: it simply ends on the expiry date shown in Profile → '
            'Premium. To continue, buy a new period from the same page.'),
  ]),
  FaqSection('Rewards & coins', Icons.monetization_on_rounded, [
    FaqItem('How do I earn coins?',
        answer: 'Rewards → Earn: daily claim (30), daily streak (20), browse 10 minutes (10), explore '
            'businesses (30), use NOVA AI (10), visual search (5), complete your profile (5), set NOVA X as '
            'default browser (50) and finish the NOVA assistant setup (100). The last two are held only '
            'while the setting stays on.'),
    FaqItem('Why were coins taken back?',
        answer: 'The default-browser (50) and NOVA setup (100) rewards are only kept while those settings stay '
            'on. Turning one off takes its coins back; turning it on again gives them back.'),
    FaqItem('When do daily tasks reset?',
        answer: 'Daily tasks reset once a day at 00:00 GMT (the NOVA X server day), wherever you are.'),
  ]),
  FaqSection('NOVA AI & Hey NOVA', Icons.auto_awesome_rounded, [
    FaqItem('Why did NOVA AI say I reached a limit?',
        answer: 'To keep NOVA fast and fair, each plan has limits every 24 hours: Free 40 messages, 5 photo '
            'uploads, 5 images; AI Boost doubles them for 24 hours (60 coins); Premium 300 messages, 30 '
            'uploads, 20 images and 3 videos. The countdown shows when they reset. Opening pages, music, '
            'speed tests and other commands are always free.'),
    FaqItem('"Hey NOVA" does not respond', askNova: true),
    FaqItem('Can NOVA control music, open pages and test my internet?', askNova: true),
    FaqItem('Does NOVA record what I say?',
        answer: 'No. "Hey NOVA" is detected on your phone; audio is only sent to NOVA AI after the wake '
            'phrase, to understand your request, and recordings are not stored.'),
  ]),
  FaqSection('Account & privacy', Icons.shield_rounded, [
    FaqItem('I forgot my password',
        answer: 'On the login screen tap "Forgot password?", enter your email and use the 6-digit code we '
            'send you to set a new password.'),
    FaqItem('How do I delete my account?',
        answer: 'Profile → Delete account. Choose a reason, confirm, and your account and data are deleted.'),
    FaqItem('Why are my notifications at the wrong time?',
        answer: 'Since NOVA X 3.9.0 greetings follow your phone\'s time zone. Open the app once after '
            'travelling so NOVA X learns your new time zone. You can turn greetings off in Settings.'),
  ]),
];
