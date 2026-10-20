// lib/features/nova/screens/nova_settings_screen.dart
//
// NOVA assistant settings: digital-assistant role, voice options (including
// the NOVA voice picker), permissions, "Hey NOVA" wake word and privacy
// information.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../models/nova_models.dart';
import '../nova_launcher.dart';
import '../services/nova_native.dart';
import '../services/nova_prefs.dart';
import '../services/nova_voice.dart';
import '../services/nova_wake.dart';
import '../widgets/nova_orb.dart';
import '../widgets/nova_voice_picker.dart';

class NovaSettingsScreen extends StatefulWidget {
  const NovaSettingsScreen({super.key});

  @override
  State<NovaSettingsScreen> createState() => _NovaSettingsScreenState();
}

class _NovaSettingsScreenState extends State<NovaSettingsScreen> with WidgetsBindingObserver {
  final NovaNativeApi _native = NovaNative.instance;
  final ValueNotifier<double> _still = ValueNotifier<double>(0);

  NovaSettings _settings = const NovaSettings();
  NovaAssistantStatus? _assistant;
  bool _mic = false;
  bool _contacts = false;
  bool _audio = false;
  bool _loading = true;
  NovaWakeStatus _wake = const NovaWakeStatus();
  bool _wakeBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _still.dispose();
    super.dispose();
  }

  // Coming back from Android settings → re-read role and permissions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final settings = await NovaPrefs.load();
    final assistant = await _native.assistantStatus();
    final mic = await _native.isPermissionGranted('microphone');
    final contacts = await _native.isPermissionGranted('contacts');
    final audio = await _native.isPermissionGranted('audio');
    final wake = await NovaWake.status();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _assistant = assistant;
      _mic = mic;
      _contacts = contacts;
      _audio = audio;
      _wake = wake;
      _loading = false;
    });
  }

  Future<void> _setWake(bool on) async {
    if (_wakeBusy) return;
    setState(() => _wakeBusy = true);
    try {
      if (on) {
        if (!await _native.isPermissionGranted('microphone') &&
            !await _native.requestPermission('microphone')) {
          _snack('"Hey NOVA" needs the microphone.', settings: true);
          return;
        }
        // Android 13+: needed for the listening notification and "tap to talk".
        await _native.requestPermission('notifications');
        final started = await NovaWake.setEnabled(true);
        if (!started) _snack("Android didn't let NOVA start listening. Keep NOVA X open and try again.");
      } else {
        await NovaWake.setEnabled(false);
      }
      // The service needs a moment to start or stop.
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } finally {
      if (mounted) {
        setState(() => _wakeBusy = false);
        await _refresh();
      }
    }
  }

  void _snack(String text, {bool settings = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      action: settings
          ? SnackBarAction(label: 'Open', onPressed: _native.openAppPermissionSettings)
          : null,
    ));
  }

  String _wakeSubtitle() {
    final w = _wake;
    if (!w.enabled) {
      return w.background
          ? 'Say "Hey NOVA" to call NOVA, even in other apps'
          : 'Say "Hey NOVA" to call NOVA while NOVA X is open';
    }
    if (w.running) return 'Listening on this phone — say "Hey NOVA"';
    if (w.error == 'microphone') return 'Needs microphone access';
    return 'Starts again when you open NOVA X';
  }

  Future<void> _save(NovaSettings s) async {
    setState(() => _settings = s);
    await NovaPrefs.save(s);
  }

  Future<void> _pickVoice() async {
    await showNovaVoicePicker(
      context,
      current: _settings.voice,
      onSelected: (key) => _save(_settings.copyWith(voice: key)),
    );
  }

  Widget _voiceTile() {
    final voice = NovaVoiceCatalog.byKey(_settings.voice);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leading(Icons.graphic_eq_rounded, AppTheme.accentCyan),
      title: Text('NOVA voice',
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(
          voice == null ? 'Choose how NOVA sounds' : '${voice.label} \u2014 ${voice.description}',
          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
      onTap: _pickVoice,
    );
  }

  Future<void> _setAsAssistant() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Make NOVA your assistant',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Android will open "Digital assistant app". Tap it and choose NOVA X.\n\n'
          'Then long-press Home, hold the power button or use the assistant gesture '
          '(depending on your phone) to call NOVA from any app.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Not now', style: GoogleFonts.inter(color: AppTheme.textHint)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan, foregroundColor: Colors.black),
            child: Text('Open settings', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (go == true) {
      final opened = await _native.openAssistantSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't open Android settings on this phone.")));
      }
    }
  }

  Future<void> _requestPermission(String kind) async {
    final granted = await _native.requestPermission(kind);
    await _refresh();
    if (granted || !mounted) return;
    // Android stops showing the dialog after repeated denials; offer Settings.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Permission not granted. You can allow it in NOVA X app settings.'),
      action: SnackBarAction(label: 'Open', onPressed: _native.openAppPermissionSettings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        foregroundColor: AppTheme.textPrimary,
        title: Text('NOVA Assistant',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _hero(),
                _section('Digital assistant'),
                _assistantCard(),
                _section('Voice'),
                _card([
                  _voiceTile(),
                  _switch(
                    Icons.record_voice_over_rounded,
                    'Speak replies aloud',
                    'NOVA reads answers in your NOVA voice (your phone\'s own voice when offline)',
                    _settings.speakReplies,
                    (v) => _save(_settings.copyWith(speakReplies: v)),
                  ),
                  _switch(
                    Icons.waving_hand_rounded,
                    'Greet when activated',
                    '"Hi, NOVA is active to assist you."',
                    _settings.greetOnActivate,
                    (v) => _save(_settings.copyWith(greetOnActivate: v)),
                  ),
                ]),
                _section('Permissions'),
                _card([
                  _permissionTile(
                    Icons.mic_rounded,
                    'Microphone',
                    'Used only after you tap the mic or call NOVA',
                    _mic,
                    () => _requestPermission('microphone'),
                  ),
                  _permissionTile(
                    Icons.contacts_rounded,
                    'Contacts',
                    'Used only when you ask NOVA to call someone by name. '
                        'Searched on this phone; never uploaded',
                    _contacts,
                    () => _requestPermission('contacts'),
                  ),
                  _permissionTile(
                    Icons.library_music_rounded,
                    'Music and audio',
                    'Used only so NOVA Music can find and play the songs saved on this phone. '
                        'Your music list never leaves your phone',
                    _audio,
                    () => _requestPermission('audio'),
                  ),
                ]),
                _section('Hands-free "Hey NOVA"'),
                ..._wakeSection(),
                _section('Privacy'),
                _infoCard(
                  Icons.privacy_tip_outlined,
                  'What NOVA sends',
                  '• Your voice is recorded only while the NOVA panel shows "Listening".\n'
                      '• The recording is sent to the NOVA AI service to be turned into text, '
                      'then deleted from your phone.\n'
                      '• Your message and the last few messages of the current conversation '
                      'are sent so NOVA can answer.\n'
                      '• Spoken replies: the reply text is sent to the NOVA Voice service '
                      '(Tech Lyfe, using Microsoft\'s online voices) to create the audio. '
                      'The audio is played, then deleted from your phone.\n'
                      '• "Hey NOVA" listens on your phone only: sound is checked in memory and '
                      'never recorded, kept or sent until NOVA opens.\n'
                      '• Voice-assistant conversations are not saved after you close NOVA. '
                      'NOVA AI chats are kept in your chat history (on this phone, and in your '
                      'NOVA X account when you are signed in) until you delete them.\n'
                      '• NOVA Music plays songs from this phone, even offline. '
                      'Your music list never leaves your phone.\n'
                      '• Contacts never leave your phone.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => showNovaAssistant(context),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text('Try NOVA now',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hero() {
    final held = _assistant?.held ?? false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.accentCyan.withOpacity(0.12), AppTheme.accentPurple.withOpacity(0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          NovaOrb(state: NovaState.idle, level: _still, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOVA',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(
                  held
                      ? 'Your digital assistant — available from any app.'
                      : 'Your assistant in NOVA X. Set it as your digital assistant to use it anywhere.',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantCard() {
    final a = _assistant;
    final supported = a?.supported ?? false;
    final held = a?.held ?? false;
    final String subtitle;
    if (!supported) {
      subtitle = 'This phone does not offer a digital-assistant choice for apps.';
    } else if (held) {
      subtitle = 'NOVA X is your digital assistant ✓';
    } else {
      subtitle = 'Not set — Android currently uses another assistant.';
    }
    return _card([
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: _leading(Icons.assistant_rounded, held ? AppTheme.success : AppTheme.accentCyan),
        title: Text('Digital assistant app',
            style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: GoogleFonts.inter(
                color: held ? AppTheme.success : AppTheme.textHint, fontSize: 11.5)),
        trailing: supported && !held
            ? TextButton(
                onPressed: _setAsAssistant,
                child: Text('Set',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
              )
            : held
                ? const Icon(Icons.check_circle_rounded, color: AppTheme.success)
                : null,
      ),
    ]);
  }

  List<Widget> _wakeSection() {
    final w = _wake;
    if (!w.supported) {
      return [
        _infoCard(
          Icons.hearing_disabled_rounded,
          'Not supported on this phone',
          'The on-device "Hey NOVA" detector can\'t run on this phone\'s processor. '
              'Call NOVA with the assistant gesture or the NOVA button instead.',
        ),
      ];
    }
    return [
      _card([
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          secondary: _leading(Icons.hearing_rounded, AppTheme.accentCyan),
          title: Text('Hey NOVA',
              style: GoogleFonts.inter(
                  color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(_wakeSubtitle(),
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
          value: w.enabled,
          activeColor: AppTheme.accentCyan,
          onChanged: _wakeBusy ? null : _setWake,
        ),
        if (w.enabled && w.background)
          _permissionTile(
            Icons.open_in_new_rounded,
            'Open NOVA over other apps',
            'Allow "Display over other apps" so "Hey NOVA" opens NOVA straight away. '
                'Without it, NOVA shows a notification you tap.',
            w.overlay,
            NovaWake.openOverlaySettings,
          ),
        if (w.enabled && !w.notifications)
          _permissionTile(
            Icons.notifications_active_outlined,
            'Notifications',
            'Shows that NOVA is listening, and the "tap to talk" alert',
            false,
            () => _requestPermission('notifications'),
          ),
      ]),
      const SizedBox(height: 10),
      _infoCard(
        Icons.info_outline_rounded,
        'How "Hey NOVA" works',
        '• Say "Hey NOVA" (or "Hello NOVA" / "Okay NOVA"), wait for the panel, then speak.\n'
            '• A notification shows while NOVA listens. Turn it off here or from the notification.\n'
            '• It runs on your phone and uses some battery while on.\n'
            '• After the phone restarts, open NOVA X once to start listening again.\n'
            '• NOVA pauses during calls and while you use NOVA itself.'
            '${w.background ? '' : '\n• On this Android version NOVA listens only while NOVA X is open.'}',
      ),
    ];
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(label.toUpperCase(),
            style: GoogleFonts.inter(
                color: AppTheme.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(children: children),
      );

  Widget _leading(IconData icon, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      );

  Widget _switch(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: _leading(icon, AppTheme.accentCyan),
      title: Text(title,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
      value: value,
      activeColor: AppTheme.accentCyan,
      onChanged: onChanged,
    );
  }

  Widget _permissionTile(
      IconData icon, String title, String subtitle, bool granted, VoidCallback onRequest) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _leading(icon, granted ? AppTheme.success : AppTheme.warning),
      title: Text(title,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
      trailing: granted
          ? Text('Allowed',
              style: GoogleFonts.inter(
                  color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w600))
          : TextButton(
              onPressed: onRequest,
              child: Text('Allow',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _infoCard(IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _leading(icon, AppTheme.accentPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(body,
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary, fontSize: 12.5, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
