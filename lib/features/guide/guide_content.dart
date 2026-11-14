// lib/features/guide/guide_content.dart
//
// NOVA X Feature Guide — what every NOVA X for Android feature does, how it
// works and how to use it well. Opened from the menu, Settings › Help and
// the "Read more" links next to features. Each section has a stable id used
// by those links (test/guide/guide_test.dart checks every link).
//
// 3.13.0: adapted from the NOVA X for PC guide. PC-only features (sidebar,
// memory saver, command palette, tray, Capture Studio, containers…) are
// left out; Android-only features (default assistant, assist button, voice
// calls & texts, NOVA Map) are added. Write for users: plain words, real
// behaviour, honest limits.

import 'package:flutter/material.dart';

class GuideSection {
  const GuideSection({
    required this.id,
    required this.category,
    required this.title,
    required this.icon,
    required this.summary,
    this.where = '',
    this.how = const [],
    this.steps = const [],
    this.tips = const [],
    this.limits = const [],
  });

  final String id;
  final String category;
  final String title;
  final IconData icon;

  /// One or two sentences: what it is and why it matters.
  final String summary;

  /// Where to find it in NOVA X.
  final String where;

  /// How it works (what NOVA X does behind the scenes).
  final List<String> how;

  /// How to use it, step by step.
  final List<String> steps;

  /// Tips for using it well.
  final List<String> tips;

  /// What it doesn't do (honest limits).
  final List<String> limits;

  /// All text, lower-case (for the guide's search box).
  String get searchText =>
      [title, summary, where, ...how, ...steps, ...tips, ...limits].join(' ').toLowerCase();
}

class GuideCategory {
  static const String start = 'Getting started';
  static const String security = 'Privacy & security';
  static const String ai = 'NOVA AI';
  static const String create = 'Capture & create';
  static const String everyday = 'Everyday browsing';
  static const String pro = 'Developer & Pro tools';
  static const String account = 'Account & services';

  static const List<String> order = [start, security, ai, everyday, create, pro, account];
}

GuideSection? guideSection(String id) {
  for (final s in kGuide) {
    if (s.id == id) return s;
  }
  return null;
}

const List<GuideSection> kGuide = [
  // ── Getting started ──────────────────────────────────────────────────────
  GuideSection(
    id: 'tabs',
    category: GuideCategory.start,
    title: 'Tabs',
    icon: Icons.tab_rounded,
    summary: 'Keep several pages open and switch between them; your tabs are remembered when you come back.',
    where: 'Tabs button in the browser toolbar',
    how: [
      'Every tab is a page in Android System WebView, the same engine as Chrome on your phone.',
      'Open tabs and their addresses are saved on this phone and shown again in the tab switcher.',
    ],
    steps: [
      'Tap the tabs button to see your tabs; tap one to open it, swipe or tap × to close it.',
      'Use the + in the tab switcher for a new tab.',
    ],
  ),
  GuideSection(
    id: 'default_browser',
    category: GuideCategory.start,
    title: 'Make NOVA X your default browser',
    icon: Icons.public_rounded,
    summary: 'Links you tap in other apps (messages, email, chats) open in NOVA X, with NOVA Shield protecting them.',
    where: 'Settings › Default browser · Rewards (a reward task)',
    how: [
      'Android asks you to confirm: NOVA X opens Android\'s own "default browser" choice for you.',
      'NOVA X checks with Android when you come back and shows whether it is now the default.',
    ],
    steps: [
      'Tap "Set as default" and choose NOVA X in the Android window.',
      'On some phones Android opens Settings › Default apps › Browser app instead; pick NOVA X there.',
    ],
  ),
  GuideSection(
    id: 'incognito',
    category: GuideCategory.start,
    title: 'Incognito tabs',
    icon: Icons.person_off_outlined,
    summary: 'Browse without saving history, and with cookies and cache cleared when you close the tab.',
    where: 'Menu › Incognito',
    how: [
      'Pages you visit in incognito aren\'t added to history, and NOVA AI Playback, Scam Explainer\'s AI and Safe NOVA Agent aren\'t used there.',
      'When you close the incognito tab, cookies and the cache are cleared.',
      'NOVA Shield and fingerprint protection keep working in incognito.',
    ],
    steps: ['Open Menu › Incognito. Incognito tabs have a purple look so you can tell them apart.'],
    limits: [
      'Incognito hides your browsing on this phone, not from the sites, your network or your mobile operator.',
      'Downloads are turned off in incognito tabs.',
    ],
  ),

  // ── Privacy & security ───────────────────────────────────────────────────
  GuideSection(
    id: 'security_center',
    category: GuideCategory.security,
    title: 'Security Center',
    icon: Icons.health_and_safety_rounded,
    summary: 'One screen for every NOVA X protection: what\'s on, what it has done, and the settings for each.',
    where: 'Menu › Security · browser menu › Security Center · Settings › Security & Passwords',
    how: [
      'Every number shown comes from a real event on this phone (a blocked request, a stopped password). Nothing is estimated.',
      'Everything is processed on this phone. The Security Center doesn\'t send your browsing to a NOVA server.',
    ],
    steps: [
      'Open the Security Center to see blocked requests today and in total, and the state of each protection.',
      'Use each card\'s switch to turn that protection on or off, and its "Read more" for details.',
      'Tap "Run self-test" after updating NOVA X to prove each protection works on this phone.',
    ],
  ),
  GuideSection(
    id: 'shield',
    category: GuideCategory.security,
    title: 'NOVA Shield blocking (ads, trackers, miners)',
    icon: Icons.block_rounded,
    summary: 'Stops ad, tracking and crypto-mining requests inside NOVA X before they leave your phone. '
        'Pages load faster, use less mobile data and fewer companies follow you around the web.',
    where: 'Settings › Ad & tracker blocker · browser menu › Ad & tracker blocker · Security Center › NOVA Shield',
    how: [
      'Every request a page makes in NOVA X is checked against the block lists. A request to a listed ad, tracker or miner domain that belongs to another company (third party) gets an empty "blocked" answer and never reaches that company.',
      'The lists are EasyList and EasyPrivacy (tens of thousands of domains). NOVA X ships a copy and downloads fresh lists once a week; a broken or tiny download is ignored.',
      'The browser menu shows the real count of requests blocked on the current page. Totals per day are kept on this phone for 60 days.',
      'Only pages inside NOVA X are affected. NOVA X never blocks ads in other apps.',
    ],
    steps: [
      'Turn on the ad & tracker blocker in Settings or in the browser menu.',
      'If a site breaks (a video won\'t play, a login loops), tap the padlock in the address bar › NOVA Shield switch to pause it for that site, then reload.',
      'NOVA Shield › About the block lists › Update now downloads the newest lists immediately.',
    ],
    tips: [
      'Pausing is per site and remembered; turn it back on in Site controls or the Security Center.',
      'Compare a news site with blocking on and paused to see the difference in ads and loading time.',
    ],
    limits: [
      'Blocking is by domain: ads served from the site\'s own domain (first-party) aren\'t blocked. Page clean-up hides many of them.',
      'Every checked request takes a short trip through the app, so very heavy pages can load a little slower with blocking on.',
    ],
  ),
  GuideSection(
    id: 'page_cleanup',
    category: GuideCategory.security,
    title: 'Page clean-up (no empty ad boxes)',
    icon: Icons.cleaning_services_rounded,
    summary: 'Removes the empty spaces and ad containers left on a page after NOVA Shield blocks the ads, so the content moves up.',
    where: 'Part of NOVA Shield · Security Center › NOVA Shield › Page clean-up',
    how: [
      'When an ad frame, image or video is blocked, the box that was waiting for it (and up to three empty wrappers around it) is hidden.',
      'EasyList\'s element-hiding rules hide known ad containers: thousands of general rules and rules for specific sites, with the lists\' exceptions.',
      'General rules are only applied when an element they target actually exists on the page, so pages don\'t slow down.',
      'Rules for the site you open are added before the page\'s own scripts run, and checked again when it has loaded.',
    ],
    steps: ['Nothing to do. It follows NOVA Shield: pausing Shield on a site also turns clean-up off there.'],
    tips: ['If a page looks like something is missing, pause NOVA Shield for that site and reload to compare.'],
    limits: ['A box that still contains text is left in place on purpose, so real content is never hidden by mistake.'],
  ),
  GuideSection(
    id: 'site_controls',
    category: GuideCategory.security,
    title: 'Site Control Center',
    icon: Icons.tune_rounded,
    summary: 'Your rules for one website: blocking, JavaScript, images, pop-ups, autoplay, camera, microphone, location, '
        'fingerprint level, desktop or mobile site, and Session Shield.',
    where: 'Tap the padlock in the address bar · browser menu › Site controls',
    how: [
      'Settings are saved per site (for example news.example.com and example.com can differ; the most specific one wins).',
      'JavaScript off stops the site\'s scripts; images off stops images from downloading on that site.',
      'Camera, microphone and location can be Ask, Allow or Block. A saved Allow or Block answers the site without asking you.',
      '"Identify as" makes the site see a phone (mobile layout) or a desktop computer.',
    ],
    steps: [
      'Open a site and tap the padlock in the address bar.',
      'Change what you need and tap "Save and reload".',
      'Use "Sign out of … now" to remove the site\'s cookies and storage immediately.',
    ],
    tips: [
      'Turn pop-ups off for sites that keep opening new windows.',
      'Turn autoplay off on news sites so videos only play when you tap them.',
    ],
    limits: ['Web notifications aren\'t supported in NOVA X\'s browser, so there is no notifications setting.'],
  ),
  GuideSection(
    id: 'fingerprint',
    category: GuideCategory.security,
    title: 'Fingerprint protection',
    icon: Icons.fingerprint_rounded,
    summary: 'Stops sites from recognising your phone by tiny drawing and audio differences, a common way to track people even without cookies.',
    where: 'Security Center › Fingerprint protection (default level) · NOVA Shield · Site controls (level per site)',
    how: [
      'Trackers draw hidden images and sounds and read back the exact pixels and samples, which differ slightly from device to device.',
      'NOVA X adds tiny, invisible changes to those readings. The change is the same on one site while NOVA X runs (so sites work normally) but different on every other site and after NOVA X restarts.',
      'Strict also gives sites a generic graphics name and common CPU and memory values.',
      'The protection hides itself: to the page it looks like the browser\'s own functions.',
    ],
    steps: [
      'Leave Standard on for everyday browsing.',
      'Choose Strict in Site controls for sites you want to give as little as possible, or Off for a site that misbehaves (for example a drawing app).',
    ],
    tips: ['Test it: open browserleaks.com/canvas, note the signature, close and reopen NOVA X and open it again — it changes.'],
    limits: ['Your IP address, screen size, language and time zone are still visible to sites, as in any browser.'],
  ),
  GuideSection(
    id: 'password_guard',
    category: GuideCategory.security,
    title: 'Password Guard',
    icon: Icons.password_rounded,
    summary: 'Protects you from phishing: if you type one of your saved passwords on a site it doesn\'t belong to — such as a fake login page — '
        'NOVA X stops it from being sent and warns you.',
    where: 'Security Center › Password Guard',
    how: [
      'Your saved passwords (and ones you add by hand) are turned into one-way PBKDF2 hashes with a random salt, kept in encrypted storage. Password Guard doesn\'t keep the passwords themselves.',
      'When you type in a password field, NOVA X checks the hash in the background. If it matches a password that belongs to another site, the form, fetch, XHR, WebSocket and beacon sends from that page are held.',
      'NOVA X then refuses every upload from that tab until you decide, and the field is cleared.',
      'You choose: "Leave this page" or "This site is mine" (which adds the site to that password\'s sites).',
    ],
    steps: [
      'Saved passwords are protected automatically.',
      'To protect another important password (bank, email), Security Center › Password Guard › Protect a password, enter it and the sites it belongs to.',
      'If you see the warning on a page you didn\'t expect, close it and go to the real site by typing its address.',
    ],
    tips: ['Add your email password by hand: it unlocks every other account, so it\'s the one phishers want most.'],
    limits: ['Passwords shorter than 4 characters are not checked. It works on pages in NOVA X, not in other apps.'],
  ),
  GuideSection(
    id: 'download_verdict',
    category: GuideCategory.security,
    title: 'Download safety (app files)',
    icon: Icons.verified_user_outlined,
    summary: 'Before an app file (APK) is kept, NOVA X shows where it comes from and any warning signs.',
    where: 'Automatic when a page downloads an app file · Security Center › Dangerous sites and downloads',
    how: [
      'For .apk and similar app files, NOVA X checks the source: insecure http, raw IP addresses, ad links and scam-looking addresses.',
      'You choose to cancel the download or keep it in Downloads.',
      'NOVA X never installs apps. If you install one later, Android\'s own installer asks you, with its own warnings.',
    ],
    steps: ['Read where the file comes from. If you didn\'t expect an app file, cancel the download.'],
    tips: ['Install apps from Google Play whenever you can; never from a link in a message from someone you don\'t know.'],
    limits: ['NOVA X can\'t tell whether an app file itself is harmful — only whether where it came from looks risky.'],
  ),
  GuideSection(
    id: 'session_shield',
    category: GuideCategory.security,
    title: 'Session Shield (auto sign-out)',
    icon: Icons.logout_rounded,
    summary: 'Signs you out of chosen sites (bank, email, admin panels) when NOVA X closes, after you\'ve been away, or with one tap — '
        'so a stolen session or a borrowed phone doesn\'t give access to them.',
    where: 'Site controls › "Sign out when NOVA X closes" · Security Center › Session Shield',
    how: [
      'For the sites you choose, NOVA X deletes their cookies and site storage — what keeps you signed in.',
      'This happens when NOVA X closes and every time it starts (Android sometimes closes apps without warning, so start-up catches anything missed), after the time away you choose, or when you tap "Sign out everywhere now".',
    ],
    steps: [
      'Open the site, tap the padlock › turn on "Sign out when NOVA X closes".',
      'In the Security Center choose a time (for example 15 minutes away from NOVA X) if you also want sign-out when you step away.',
    ],
  ),
  GuideSection(
    id: 'shield_dns',
    category: GuideCategory.security,
    title: 'Dangerous-site protection (Safe Browsing, DNS check, HTTPS)',
    icon: Icons.gpp_good_outlined,
    summary: 'Known malware and phishing pages are blocked, and connections are upgraded to secure HTTPS when possible.',
    where: 'NOVA Shield · Security Center › Dangerous sites and downloads',
    how: [
      'Google Safe Browsing (part of Android System WebView) checks pages against Google\'s threat lists.',
      'NOVA Shield\'s malware check looks up each site you open with a filtering DNS service over HTTPS and shows a block page if it\'s known to be dangerous. Only the site\'s name is sent.',
      'HTTPS upgrade loads the secure version of a site when you open an http address.',
    ],
    steps: ['Leave these on. NOVA Shield Pro lets you choose the DNS provider.'],
    limits: ['Brand-new scam sites may not be on any list yet — Scam Explainer and Password Guard help in those cases.'],
  ),
  GuideSection(
    id: 'self_test',
    category: GuideCategory.security,
    title: 'Security self-test',
    icon: Icons.fact_check_rounded,
    summary: 'Proves on your phone that each protection actually works, using the real blocking code and scripts — not a simulation.',
    where: 'Security Center › Run self-test',
    how: [
      'Opens a hidden page on example.com (a domain reserved for tests) and checks: the block lists, blocking decisions, live blocking, fingerprint protection, Password Guard, Session Shield and download safety.',
      'It uses a temporary test password and a test cookie; nothing is sent to real sites and nothing of yours is changed.',
    ],
    steps: ['Tap Run self-test and wait about 15 seconds. Every line should say PASS. Run it again after updating NOVA X.'],
    limits: ['Needs an internet connection. Live blocking passes only while the ad & tracker blocker is on.'],
  ),
  GuideSection(
    id: 'passwords',
    category: GuideCategory.security,
    title: 'Password manager',
    icon: Icons.key_rounded,
    summary: 'Saves your passwords, offers them on the right site and keeps them behind your fingerprint, face or screen lock.',
    where: 'Settings › Saved passwords · offer appears after you sign in to a site',
    how: [
      'Passwords are stored in Android\'s encrypted storage on this phone.',
      'Before a saved password is filled, NOVA X asks for your fingerprint, face or screen lock.',
      'Saved passwords are automatically protected by Password Guard.',
    ],
    steps: [
      'Sign in to a site and choose Save when NOVA X asks.',
      'Next time, tap "Sign in" on the "Use saved password?" sheet and confirm it\'s you.',
    ],
  ),
  GuideSection(
    id: 'open_safely',
    category: GuideCategory.security,
    title: 'Open Safely and Safe View',
    icon: Icons.health_and_safety_outlined,
    summary: 'Check where a suspicious link really goes before opening it, then open it in a locked-down Safe View tab.',
    where: 'Browser menu › Page tools › Open a link safely…',
    how: [
      'NOVA X follows the link\'s redirects one by one without loading the page and shows every address on the way and where it ends.',
      'The final address is checked by Scam Explainer\'s address checks and NOVA Shield.',
      'Safe View is an incognito tab with scripts off, downloads blocked, and camera, microphone and location refused.',
    ],
    steps: [
      'Copy a link from a message, open Open a link safely… (a copied link is filled in for you) and tap Check.',
      'Read where it ends up. If it\'s fine, open it normally; if unsure, open it in Safe View.',
    ],
    limits: ['Many sites don\'t work without scripts, so Safe View is for looking, not for signing in or buying.'],
  ),
  GuideSection(
    id: 'scam_explainer',
    category: GuideCategory.security,
    title: 'Scam Explainer',
    icon: Icons.gpp_maybe_outlined,
    summary: 'Explains in plain words why a page might be a scam — look-alike addresses, pressure tactics, gift-card payments, recovery-phrase requests.',
    where: 'Browser menu › Page tools › Scam Explainer',
    how: [
      'Checks the address (brand look-alikes, odd characters, raw IP, risky endings, no HTTPS) and the page (prizes, urgency, gift-card or crypto payment, seed phrases, forms sending data to other sites).',
      'Gives a score with each reason explained. Optionally NOVA AI explains the page in simple terms (not in incognito tabs).',
    ],
    steps: ['On a page you\'re unsure about — for example a link from an SMS or WhatsApp — open Page tools › Scam Explainer and read the reasons.'],
    limits: ['It\'s a set of warning signs, not a guarantee. When money or passwords are involved, go to the company\'s site yourself.'],
  ),
  GuideSection(
    id: 'clear_data',
    category: GuideCategory.security,
    title: 'Clearing browsing data',
    icon: Icons.cleaning_services_outlined,
    summary: 'Remove history, cookies, cache and site data — for everything or for one site.',
    where: 'Settings › Privacy & Data · browser menu › Clear page data · browser menu › Cookie Editor',
    how: [
      '"Clear page data" removes cookies, cache and storage and reloads the page (you\'ll be signed out there).',
      'The cookie editor lets you see, edit or delete cookies of the current site.',
    ],
    steps: ['Choose what to clear, then confirm.'],
  ),

  // ── NOVA AI ──────────────────────────────────────────────────────────────
  GuideSection(
    id: 'nova_ai',
    category: GuideCategory.ai,
    title: 'NOVA AI',
    icon: Icons.auto_awesome_rounded,
    summary: 'Your assistant for questions, writing, explanations, images and help with what you\'re browsing.',
    where: 'Menu › NOVA AI',
    how: [
      'Messages are sent to NOVA AI to get an answer; your chats are kept on this phone so you can continue them.',
      'You can attach photos for NOVA to look at. Images NOVA creates are saved in their chat, and NOVA remembers what it created when you ask about it.',
      'NOVA AI messages count toward your plan\'s limit; Premium raises it.',
    ],
    steps: [
      'Open NOVA AI, type your question and tap send.',
      'Tap the microphone to speak instead of typing. Type /image or /video followed by a description to create one.',
    ],
    tips: ['Be specific: say what you want, for whom and how long ("a 3-sentence polite reply declining the meeting").'],
    limits: ['AI can be wrong. Check important facts, numbers and medical, legal or financial information.'],
  ),
  GuideSection(
    id: 'hey_nova',
    category: GuideCategory.ai,
    title: 'Hey NOVA',
    icon: Icons.record_voice_over_outlined,
    summary: 'Say "Hey NOVA" to ask questions, open apps and settings, play music or take a screenshot — without touching the phone.',
    where: 'NOVA settings (from NOVA AI or Settings › NOVA Assistant)',
    how: [
      'The "Hey NOVA" wake word is detected on your phone by a small on-device model; audio isn\'t sent anywhere until NOVA wakes up.',
      'After waking, your request is understood by NOVA AI. Actions like opening apps, Android settings pages or NOVA Music run on the phone.',
      'A notification shows while Hey NOVA is listening.',
    ],
    steps: [
      'Turn on Hey NOVA in NOVA settings and allow the microphone.',
      'Say "Hey NOVA", wait for the sound, then speak — for example "open Wi-Fi settings" or "play some music".',
    ],
    limits: ['Hey NOVA pauses while another app uses the microphone (for example during a call).'],
  ),
  GuideSection(
    id: 'assistant',
    category: GuideCategory.ai,
    title: 'NOVA as your phone\'s assistant',
    icon: Icons.assistant_rounded,
    summary: 'Make NOVA the assistant that opens when you long-press the home button, swipe from a corner or press your phone\'s assist button.',
    where: 'NOVA settings › Digital assistant app · Android Settings › Apps › Default apps › Digital assistant app',
    how: [
      'Android lets you choose one assistant app. When NOVA is chosen, the assist gesture or button opens NOVA\'s floating panel over the app you\'re in.',
      'The panel can answer questions, read your screen when you ask ("what\'s on my screen?") and run phone commands.',
    ],
    steps: [
      'Open NOVA settings › Digital assistant app; Android opens its own screen — choose NOVA X.',
      'Long-press home (or use your phone\'s assist gesture) to open NOVA.',
    ],
    limits: ['Which gesture or button opens the assistant depends on your phone maker.'],
  ),
  GuideSection(
    id: 'voice_calls',
    category: GuideCategory.ai,
    title: 'Calls and texts by voice',
    icon: Icons.phone_in_talk_outlined,
    summary: 'Ask NOVA to call or text someone ("call Ama", "text Kofi I\'m on my way").',
    where: 'Hey NOVA · NOVA AI · the assistant panel',
    how: [
      'For names, NOVA looks them up in your contacts on the phone (with your permission); contacts aren\'t uploaded.',
      'NOVA opens your Phone or Messages app with the number (and message) ready — you press call or send.',
    ],
    steps: ['Say "Hey NOVA, call …" or "text … that …", then confirm in the Phone or Messages app.'],
    limits: ['NOVA never calls or sends a text by itself.'],
  ),
  GuideSection(
    id: 'ai_page',
    category: GuideCategory.ai,
    title: 'Summarise and ask about a page',
    icon: Icons.summarize_outlined,
    summary: 'Get the key points of a long article, or ask NOVA questions about the page you\'re reading.',
    where: 'Browser menu › Summarise with NOVA / Ask NOVA about this page',
    how: ['NOVA X reads the page\'s main text and sends it with your request to NOVA AI.'],
    steps: ['Open an article, choose Summarise with NOVA, or Ask NOVA and type a question such as "what are the risks mentioned?".'],
    limits: ['Not available in incognito tabs or on pages with password or card fields.'],
  ),
  GuideSection(
    id: 'playback',
    category: GuideCategory.ai,
    title: 'NOVA AI Playback',
    icon: Icons.play_circle_outline_rounded,
    summary: 'Listen to an article as a short conversation between two voices, Ava and Leo, while you do something else.',
    where: '▶ button in the browser toolbar (on pages with enough text)',
    how: [
      'NOVA X reads the page, NOVA AI turns it into a conversation, and it\'s played with NOVA Voice (or your phone\'s own voices).',
      'Playback pauses when NOVA X goes to the background.',
    ],
    steps: [
      'Tap ▶ on an article. Use the mini player to pause, skip and change speed.',
      'Use 👍 / 👎 to tell us how it sounded.',
    ],
    limits: ['Not offered in incognito tabs or on pages with password or card fields. Free plan: a limited number of plays a day; Premium: unlimited.'],
  ),
  GuideSection(
    id: 'nova_agent',
    category: GuideCategory.ai,
    title: 'Safe NOVA Agent',
    icon: Icons.smart_toy_outlined,
    summary: 'Tell NOVA what to do on a page ("find the cheapest flight", "fill the contact form with my name") and approve each step as it works.',
    where: 'Browser menu › Page tools › Safe NOVA Agent',
    how: [
      'NOVA looks at the page, proposes one step (tap, type, choose, scroll, open) and highlights the element. Nothing happens until you tap Approve.',
      'It works only inside NOVA X\'s browser, through the page itself — it never controls other apps and doesn\'t use accessibility access.',
      'It uses the tab as it is, including the accounts signed in there.',
      'Text on web pages is treated as untrusted: instructions hidden in a page are ignored. Moving to a different website always needs your approval.',
      'It never types into password, card or one-time-code fields, marks buying, sending and deleting steps in red, and stops after 30 steps.',
    ],
    steps: [
      'Open the page, start Safe NOVA Agent, type the goal and tap Start.',
      'Read each proposed step. Approve, Skip or Stop. Red steps can spend money or send something — check carefully.',
    ],
    tips: ['Give clear goals with the details NOVA needs ("search for flights Accra → Dubai on 12 December, one adult").'],
    limits: ['Each step uses one NOVA AI message. It doesn\'t run in incognito or Safe View tabs.'],
  ),

  // ── Everyday browsing ────────────────────────────────────────────────────
  GuideSection(
    id: 'new_tab',
    category: GuideCategory.everyday,
    title: 'Home, Quick Access and Customize',
    icon: Icons.grid_view_rounded,
    summary: 'Search, your favourite sites, features and news on the home screen — with your own background and layout.',
    where: 'Home screen · Menu › Customize',
    how: [
      'Quick Access tiles are your pinned sites. The search box uses the search engine you pick; Lens lets you search with a picture.',
    ],
    steps: ['Menu › Customize to change Quick Access tiles, the background and what the home screen shows.'],
  ),
  GuideSection(
    id: 'library',
    category: GuideCategory.everyday,
    title: 'Bookmarks, history and downloads',
    icon: Icons.bookmarks_outlined,
    summary: 'Keep sites you like, find pages you visited and see what you downloaded.',
    where: 'Star in the browser toolbar · Menu › Bookmarks / History / Downloads',
    how: [
      'Bookmarks and history are stored on this phone. Incognito tabs don\'t add history.',
      'App files (APK) are checked by download safety before they are kept.',
    ],
    steps: ['Tap the star to bookmark a page. Open History or Downloads from the menu.'],
  ),
  GuideSection(
    id: 'reading',
    category: GuideCategory.everyday,
    title: 'Reader mode, offline pages and text size',
    icon: Icons.chrome_reader_mode_outlined,
    summary: 'Read articles without clutter, save pages to read without internet, and make text bigger or smaller.',
    where: 'Browser menu › Reader Mode / Save page offline / Offline pages',
    how: [
      'Reader mode shows the article text in a clean layout with your choice of theme and font size.',
      '"Save page offline" stores the page on this phone (Menu › Offline pages).',
    ],
    steps: ['Open an article and choose Reader Mode; choose it again to go back.'],
  ),
  GuideSection(
    id: 'settings',
    category: GuideCategory.everyday,
    title: 'Settings',
    icon: Icons.settings_outlined,
    summary: 'Search engine, NOVA Shield, passwords, privacy, help and account settings.',
    where: 'Menu › Settings',
    steps: ['Open Settings for general options, the Security Center and this guide (Help › Feature Guide).'],
  ),

  // ── Capture & create ─────────────────────────────────────────────────────
  GuideSection(
    id: 'capture',
    category: GuideCategory.create,
    title: 'NOVA Capture (screenshots and screen recording)',
    icon: Icons.screenshot_monitor_rounded,
    summary: 'Take screenshots of a page or the screen, record your screen, and keep everything in one library.',
    where: 'Menu › NOVA Capture · browser menu › Screenshot & record · "Hey NOVA, take a screenshot"',
    how: [
      'Android asks your permission each time a screen recording starts.',
      'My captures shows everything with preview, share and delete.',
    ],
    steps: ['Open NOVA Capture and choose screenshot or recording, or ask Hey NOVA.'],
  ),
  GuideSection(
    id: 'music',
    category: GuideCategory.create,
    title: 'NOVA Music',
    icon: Icons.library_music_outlined,
    summary: 'Play the songs on your phone with a queue, shuffle and repeat — also by voice.',
    where: 'Menu › NOVA Music',
    how: ['NOVA Music lists audio files on this phone (with your permission); nothing is uploaded.'],
    steps: ['Open NOVA Music and tap a song. Say "Hey NOVA, play …" to play by voice.'],
  ),

  // ── Developer & Pro tools ────────────────────────────────────────────────
  GuideSection(
    id: 'devtools',
    category: GuideCategory.pro,
    title: 'Developer tools',
    icon: Icons.developer_mode_rounded,
    summary: 'Inspect and debug pages on your phone: console, network requests, elements and page sources.',
    where: 'Home › Features › Dev Tools · browser menu › Developer tools',
    how: ['NOVA developer tools show the page\'s console, network requests, elements and sources in a NOVA panel.'],
    steps: ['Open a page, open Developer tools and pick a tab (Console, Network, Elements, Sources).'],
  ),
  GuideSection(
    id: 'rewrite_rules',
    category: GuideCategory.pro,
    title: 'Rewrite Rules, Low-Data and Annoyance Mode',
    icon: Icons.tune_rounded,
    summary: 'Redirect, block, restyle or add scripts to any site — and browse lighter by blocking heavy files and hiding pop-ups.',
    where: 'Browser menu › Page tools › Rewrite Rules · Page tools switches',
    how: [
      'Redirect rules send one address pattern to another (* matches anything, \$1 reuses it). Block rules stop matching requests.',
      'Site CSS and site JS run on the sites you choose.',
      'Low-Data mode stops images, video files and web fonts from downloading — useful on mobile data. Annoyance mode hides cookie banners, sign-up pop-ups and sticky overlays, and stops self-starting videos.',
      'Rules apply only inside NOVA X.',
    ],
    steps: ['Add a rule, test it in the test box, and import/export rules to share them.'],
  ),
  GuideSection(
    id: 'security_lens',
    category: GuideCategory.pro,
    title: 'Security Lens',
    icon: Icons.policy_outlined,
    summary: 'A passive security review of the site you\'re on: HTTPS, security headers, cookies, mixed content and more, graded A–F.',
    where: 'Browser menu › Page tools › Security Lens',
    how: [
      'Reads what the site already sends (certificate, headers, cookies, page content) with one normal request. It doesn\'t attack or scan the site.',
      'Each finding explains the risk and how to fix it; copy or save a Markdown report.',
    ],
    steps: ['Open your site, run Security Lens and work through the findings from high to low.'],
  ),
  GuideSection(
    id: 'site_xray',
    category: GuideCategory.pro,
    title: 'Site Data X-ray',
    icon: Icons.manage_search_rounded,
    summary: 'See what a site stores on your phone and which other companies it loads from — and remove or block them.',
    where: 'Browser menu › Page tools › Site Data X-ray',
    how: [
      'Lists the site\'s cookies, local and session storage, IndexedDB databases, caches, background workers and permissions.',
      'Shows every other company the page loaded from (ads, analytics, social, session recording) with one-tap Block (a Rewrite Rule).',
    ],
    steps: ['Open X-ray on a site, review what\'s stored, delete what you don\'t want, block trackers you see.'],
    limits: ['Android doesn\'t show cookie flags (Secure, HttpOnly) to apps; Security Lens shows the flags the site sets.'],
  ),
  GuideSection(
    id: 'xcoder',
    category: GuideCategory.pro,
    title: 'X Coder',
    icon: Icons.code_rounded,
    summary: 'A code editor inside NOVA X with syntax highlighting, files and NOVA Coder help.',
    where: 'Home › Features › X Coder',
    steps: ['Open X Coder, create or open files and edit them; ask NOVA Coder for help with your code.'],
  ),
  GuideSection(
    id: 'cyber',
    category: GuideCategory.pro,
    title: 'NOVA Cyber',
    icon: Icons.security_rounded,
    summary: 'A security check for website owners and developers: it finds the weaknesses attackers look for on your sites and in your code, '
        'proves each one with evidence, and gives the exact fix for your server.',
    where: 'Home › Features › NOVA Cyber · Menu › NOVA Cyber · browser menu › NOVA Cyber',
    how: [
      'Quick scan (any site, read-only): only reads what a normal visit and public DNS reveal — TLS certificate, HTTPS redirect, HSTS, '
          'security headers (the Content-Security-Policy is analysed, not just checked for presence), cookie flags, mixed content, '
          'insecure forms, API keys in the page, JavaScript libraries with known CVEs (checked against OSV.dev), SPF, DMARC, CAA, DNSSEC '
          'and subdomain takeover.',
      'Full scan (verified owners only): active tests — 45+ sensitive files (.env, .git, backups, database dumps, logs, debug tools), '
          'directory listing, admin and database tools, GraphQL introspection, API docs, source maps, TRACE and HTTP methods, CORS, '
          'Host-header trust, reflected XSS, SQL injection, template injection, path traversal, open redirects, WordPress users/XML-RPC/plugins, '
          'exposed database and admin ports, subdomains from certificate logs, and (optional) login rate limiting.',
      'Every test is harmless: unique inert markers and comparisons prove a weakness without changing or deleting anything. '
          'Secrets found in exposed files are never shown. Requests are rate-limited and the scan stops by itself if the site\'s firewall pushes back.',
      'Ownership is checked by the NOVA X server, not the app: you get a unique 160-bit code for your account and site; the server reads it '
          'from your DNS, a file or a meta tag (never trusting the app), keeps an audit record, and re-checks it before every full scan. '
          'Verification lasts 30 days; removing the code ends it.',
      'Results show a score (100 minus weighted findings; any critical caps it at 39, any high at 69), where points were lost, evidence, '
          'the risk in plain words, step-by-step fixes and ready-to-paste configuration for the platform NOVA Cyber detected '
          '(Nginx, Apache, IIS, Cloudflare, Vercel, Netlify, PHP, Express, WordPress).',
      'Code scan reads a project you pick on this phone — a .zip of the project or several files: hard-coded secrets, SQL/command injection, eval, '
          'unsafe deserialization, disabled TLS checks, weak password hashing, JWT "none", plus vulnerable npm, Composer, PyPI and Pub packages. '
          'Only package names and versions are sent to OSV.dev.',
    ],
    steps: [
      'Type your site and tap Run (Quick) to see the outside view.',
      'For the full scan, open Verified › Verify a site, add the code by DNS, file or HTML tag, and tap Check now.',
      'Choose Full and tap Run; confirm you own the site and pick the optional tests.',
      'Open each finding, apply the fix for your platform, then tap Re-check (or Scan again) to confirm it\'s gone.',
      'Export the report (HTML or Markdown) for your team or client.',
    ],
    tips: [
      'Use the DNS method: it verifies the domain and all its subdomains at once.',
      'Allow-list your IP in Cloudflare or your firewall before a full scan, otherwise the firewall may stop the scan early (that\'s a good sign for your security, but hides other results).',
      'Keep NOVA X open while a scan runs — leaving the app stops the scan and keeps the partial results.',
    ],
    limits: [
      'No scanner finds everything. Business-logic flaws, access control between users and authenticated areas need a manual review or a professional penetration test.',
      'Full scans are limited per day per account and per site.',
      'Only scan sites you own or are authorised to test.',
    ],
  ),
  GuideSection(
    id: 'network',
    category: GuideCategory.pro,
    title: 'NOVA Network',
    icon: Icons.speed_rounded,
    summary: 'Test your internet speed and connection quality.',
    where: 'Home › Features › NOVA Network · "Hey NOVA, test my internet speed"',
    steps: ['Open NOVA Network and start the test. Close other downloads first for an accurate result.'],
  ),

  // ── Account & services ───────────────────────────────────────────────────
  GuideSection(
    id: 'rewards',
    category: GuideCategory.account,
    title: 'Rewards and Premium',
    icon: Icons.workspace_premium_outlined,
    summary: 'Earn coins for using NOVA X and unlock features with them; Premium unlocks more NOVA AI, unlimited Playback and more.',
    where: 'Home › Features › Rewards · Menu › Go Premium',
    how: ['Coins and Premium are linked to your NOVA X account, the same on Android and PC.'],
    steps: ['Open Rewards to see your coins and how to earn more; open Premium to see what it includes.'],
  ),
  GuideSection(
    id: 'map',
    category: GuideCategory.account,
    title: 'NOVA Map',
    icon: Icons.map_outlined,
    summary: 'Maps, places and directions inside NOVA X.',
    where: 'Menu › NOVA Map',
    how: ['Your location is used only when you allow it, to show where you are and give directions.'],
  ),
  GuideSection(
    id: 'business',
    category: GuideCategory.account,
    title: 'Business directory',
    icon: Icons.storefront_outlined,
    summary: 'Find businesses listed on NOVA X, or list your own.',
    where: 'Menu › Business',
  ),
  GuideSection(
    id: 'notifications',
    category: GuideCategory.account,
    title: 'Notifications',
    icon: Icons.notifications_none_rounded,
    summary: 'Messages from NOVA X: account news, rewards, new features and important updates.',
    where: 'Bell on the home screen',
    how: ['Push notifications arrive even when NOVA X is closed, if you allowed notifications.'],
  ),
  GuideSection(
    id: 'support',
    category: GuideCategory.account,
    title: 'Help & Support',
    icon: Icons.support_agent_rounded,
    summary: 'Get help, read answers and report a problem to the NOVA X team.',
    where: 'Settings › Help & Support · Settings › Report an Issue',
    steps: ['Describe what you did, what you expected and what happened; add a screenshot if you can.'],
  ),
];
