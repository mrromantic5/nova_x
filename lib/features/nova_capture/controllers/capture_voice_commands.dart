// lib/features/nova_capture/controllers/capture_voice_commands.dart
//
// Local, deterministic recognition of NOVA Capture voice commands. It runs on
// the phone (works offline), never sends audio, screenshots or page content
// anywhere, and only ever produces one of the allow-listed intents below. The
// NOVA AI planner cannot create capture actions (see NovaActionValidator).
//
// Input is text already normalised by NovaCommandParser.normalise (lower
// case, wake phrase and "please/can you…" removed).
//
// Commands that would clash with NOVA Music ("pause", "stop") only match
// when they mention the recording ("pause the recording").

/// Every capture action NOVA can perform. Anything else is rejected.
enum CaptureIntent {
  screenshotAuto('capture.screenshot.auto'),
  screenshotWebpage('capture.screenshot.webpage'),
  screenshotFullPage('capture.screenshot.full_page'),
  screenshotFullScreen('capture.screenshot.full_screen'),
  recordingStart('capture.recording.start'),
  recordingPause('capture.recording.pause'),
  recordingResume('capture.recording.resume'),
  recordingStop('capture.recording.stop'),
  recordingCancel('capture.recording.cancel'),
  recordingStatus('capture.recording.status'),
  recordingControls('capture.recording.controls'),
  openLibrary('capture.media.open_library'),
  previewLatest('capture.media.preview_latest'),
  editLatest('capture.media.edit_latest'),
  shareLatest('capture.media.share_latest'),
  openStudio('capture.studio.open'),
  openSettings('capture.settings.open'),
  setResolution('capture.settings.resolution'),
  setOrientation('capture.settings.orientation'),
  setAudio('capture.settings.audio'),
  audioModes('capture.settings.audio_modes'),
  storage('capture.storage.status'),
  explain('capture.help.explain'),
  options('capture.help.options'),
  retry('capture.retry');

  const CaptureIntent(this.id);
  final String id;

  static CaptureIntent? fromId(String? id) {
    for (final i in values) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// A recognised command: an allow-listed intent plus validated arguments.
class CaptureCommand {
  const CaptureCommand(this.intent, [this.args = const {}]);

  final CaptureIntent intent;
  final Map<String, String> args;

  @override
  bool operator ==(Object other) =>
      other is CaptureCommand &&
      other.intent == intent &&
      other.args.length == args.length &&
      other.args.entries.every((e) => args[e.key] == e.value);

  @override
  int get hashCode => Object.hash(intent, Object.hashAllUnordered(args.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => 'CaptureCommand(${intent.id}, $args)';
}

/// A capture-related request NOVA isn't sure about: ask, don't guess.
class CaptureClarification {
  const CaptureClarification(this.question, this.options);
  final String question;

  /// Sentences the user can tap; each is submitted as if they had said it.
  final List<String> options;
}

class CaptureCommandRegistry {
  CaptureCommandRegistry._();

  /// Set by the action handler after a capture command fails, so "try again"
  /// repeats it. Cleared after a success.
  static CaptureCommand? lastFailed;

  // ── Argument rules (also used by NovaActionValidator) ─────────────────────

  static const Set<String> kinds = {'screenshot', 'recording', 'any'};
  static const Set<String> audioArgs = {'default', 'none', 'mic', 'device', 'mic_device'};
  static const Set<String> resolutionValues = {'auto', '1080', '720', '480'};
  static const Set<String> orientationValues = {'auto', 'portrait', 'landscape'};
  static const Set<String> audioValues = {'none', 'mic', 'device', 'mic_device'};

  /// Returns cleaned args for [intent], or null if any is invalid.
  static Map<String, String>? validArgs(CaptureIntent intent, Map<String, String> raw) {
    final out = <String, String>{};
    for (final e in raw.entries) {
      final ok = switch (e.key) {
        'kind' => kinds.contains(e.value),
        'audio' => intent == CaptureIntent.recordingStart && audioArgs.contains(e.value),
        'confirm' => intent == CaptureIntent.recordingCancel && e.value == 'yes',
        'value' => switch (intent) {
            CaptureIntent.setResolution => resolutionValues.contains(e.value),
            CaptureIntent.setOrientation => orientationValues.contains(e.value),
            CaptureIntent.setAudio => audioValues.contains(e.value),
            _ => false,
          },
        _ => false,
      };
      if (!ok) return null;
      out[e.key] = e.value;
    }
    if ((intent == CaptureIntent.setResolution ||
            intent == CaptureIntent.setOrientation ||
            intent == CaptureIntent.setAudio) &&
        !out.containsKey('value')) {
      return null;
    }
    return out;
  }

  // ── Vocabulary ────────────────────────────────────────────────────────────

  static const String _shot = r'(?:screenshot|screen shot|screen-shot|screengrab|screen grab|screen capture|snapshot)';
  static const String _shots = r'(?:screenshots|screen shots|screengrabs|snapshots)';
  static const String _rec = r'(?:screen recording|screen recorder|recording|recorder|screencast|screen cast|video)';
  static const String _recs = r'(?:screen recordings|recordings|videos|screencasts)';
  static const String _det = r'\s+(?:(?:the|my|this|a|an|that|current)\s+)?';
  static const String _latest = r'(?:latest|last|most recent|newest|recent)';

  static RegExp _re(String p) => RegExp(p);

  static final _explain = _re(
      r"^(?:why (?:did|didn't|did not|won't|wouldn't|isn't|is not|doesn't|does not)\b.*\b(?:record|recording|screenshot|capture)|explain why\b.*\b(?:record|recording|screenshot|capture)|what went wrong with (?:the |my )?(?:recording|screenshot|capture))");
  static final _status = _re(
      r"^(?:how long (?:have i been|has it been|has (?:the |my )?(?:screen )?recording been|is (?:the |my )?recording)(?: recording| going| running)?|is (?:the |my )?(?:screen )?recording (?:active|on|running|going|still going|still on)|is (?:my )?screen (?:being )?record(?:ed|ing)|am i (?:still )?recording(?: my screen)?|(?:screen )?recording status|are you (?:still )?recording(?: my screen)?)$");
  static final _storage = _re(
      r"^(?:how much (?:free )?(?:storage space|storage|space)(?: (?:is|do i have))?(?: left| available| free)?(?: on my phone)?(?: for recording)?|(?:check|show)(?: my)? (?:storage|free space)|(?:storage|space) left|(?:free|available) (?:storage|space))$");
  static final _audioModes = _re(
      r"^(?:(?:show|list|tell me|what are)(?: me)?(?: the)?(?: available)? (?:audio|sound) (?:modes|options)(?: for recording)?|what (?:audio|sound) can you record|which (?:audio|sound) modes(?: are there)?|available audio modes)$");
  static final _options = _re(
      r"^(?:(?:show|list|tell me|what are)(?: me)?(?: the)?(?: available)? capture options|what can you capture|capture options|what can nova capture do|how do i (?:take a screenshot|record my screen))$");
  static final _openSettings = _re(
      r"^(?:open|show|go to)?(?: the| my)? ?(?:recording|recorder|capture|screen recorder|screenshot) settings$|^change (?:the |my )?recording (?:quality|settings|resolution)$");
  static final _setResolution = _re(
      r"^(?:(?:record|recording)(?: (?:at|in))?|set (?:the )?recording (?:quality|resolution) to|change (?:the )?recording (?:quality|resolution) to|use) (1080|720|480)p?(?:\s.*)?$");
  static final _setResolutionAuto = _re(r"^(?:set|change) (?:the )?recording (?:quality|resolution) to auto(?:matic)?$");
  static final _setOrientation = _re(
      r"^(?:switch to|use|record in|set (?:the )?recording to|change to) (landscape|portrait)(?: mode)?(?: recording)?$|^(landscape|portrait) recording$");
  static final _audioOn = _re(
      r"^(?:enable|turn on|use|switch on|add) (?:the )?(?:microphone|mic)(?: narration| audio)?(?: for (?:the )?recordings?)?$|^(?:enable|turn on) narration$");
  static final _audioOff = _re(
      r"^(?:disable|turn off|switch off|stop using) (?:the )?(?:microphone|mic|narration|recording audio)(?: narration)?(?: for (?:the )?recordings?)?$|^(?:no|mute) (?:recording )?audio for recordings$");
  static final _audioDevice = _re(
      r"^(?:record|use|enable|turn on) (?:app|apps|device|internal|system|phone) (?:sound|audio)(?: for (?:the )?recordings?)?$");

  static final _controls = _re(r"^(?:show|open|bring up)(?: me)?(?: the)? (?:screen )?(?:recording|recorder) controls$");
  static final _pause = _re("^(?:pause|hold)$_det(?:screen )?(?:recording|recorder|video|screen recording)(?: for a (?:moment|second|bit))?\$");
  static final _resume = _re(
      "^(?:resume|continue|unpause|keep)$_det(?:screen )?(?:recording|recorder|video|screen recording)\$|^(?:continue|resume|keep) recording(?: my screen)?\$");
  static final _cancel = _re(
      "^(?:cancel|discard|abort|scrap|throw away|delete)$_det(?:screen )?(?:recording|video|screen recording)(?: without saving)?\$|^stop$_det(?:screen )?recording without saving\$");
  static final _stop = _re(
      "^(?:stop|end|finish|save|stop and save|end and save|finish and save)$_det(?:screen )?(?:recording|recorder|video|screen recording)(?: and save(?: it)?)?(?: now)?\$|^stop recording my screen\$");
  static final _start = <RegExp>[
    _re(r"^(?:start|begin|launch|turn on|start up|kick off)(?: a| the| my)?(?: new)? (?:screen ?recording|screen ?recorder|recording|screencast|screen cast)((?: (?:of )?(?:my|the) (?:screen|phone|display))?.*)$"),
    _re(r"^(?:start|begin) recording ((?:my|the) (?:screen|phone|display).*)$"),
    _re(r"^record (?:(?:my|the|this) )?(?:screen|phone screen|display|tutorial|video|this|it|a video of (?:my|the) screen)((?:\s.*)?)$"),
    _re(r"^(?:screen ?record)(?: my screen)?((?:\s.*)?)$"),
    _re(r"^record(?: my screen)? ((?:without|with|silently|with no)\b.*)$"),
  ];

  static final _editLatest = _re(
      "^(?:edit|crop|annotate|mark up|markup|draw on|redact|blur|rotate)(?: my| the)?(?: $_latest| this)? $_shot\$");
  static final _shareLatest = _re(
      "^(?:share|send)(?: me)?(?: my| the)?(?: $_latest)? ($_shot|$_rec|capture)\$");
  static final _previewLatest = _re(
      "^(?:open|show|play|view|see|display|watch)(?: me)?(?: my| the)? $_latest ($_shot|$_rec|capture)\$");
  static final _library = _re(
      "^(?:open|show|view|see|display|go to|list)(?: me)?(?: my| the| all| all my)?(?: (?:recent|saved|latest|all))? ($_shots|$_recs|captures|recording library|capture library|screenshot library|media library|screenshot gallery|capture gallery)\$");
  static final _studio = _re(
      r"^(?:open|launch|show|go to)(?: the| my)? (?:screenshot studio|nova capture|capture studio|screen recorder|capture dashboard|recorder|screen recording app)$");

  static final _fullPage = _re(
      "^(?:take|capture|grab|make|get)?(?: a| me a| the)? ?(?:full|whole|entire|long|scrolling|complete)(?:-| )?(?:page|webpage|web page|site) (?:$_shot|capture)(?: and save(?: it)?)?\$|^(?:capture|screenshot)(?: of)? the (?:full|whole|entire) (?:page|webpage|web page|site)\$");
  static final _fullScreen = _re(
      "^(?:take|capture|grab|get)?(?: a| me a)? ?(?:$_shot|capture)?(?: of)? ?(?:my|the|whole|entire|full|my whole|my entire|the whole|the entire) (?:phone )?(?:screen|display|device|phone)(?: screen)?(?: and save(?: it)?)?\$|^(?:entire|whole|full) screen (?:$_shot|capture)\$");
  static final _webpage = _re(
      "^(?:take|capture|grab|get)?(?: a)? ?(?:$_shot|capture|snap)?(?: of)? ?(?:this|the|current) (?:page|webpage|web page|site|website|tab)\$|^$_shot (?:this|the) (?:page|webpage|web page|site|website)\$");
  static final _auto = _re(
      "^(?:(?:take|capture|grab|make|snap|get)(?: a| me a| the| one| another)? )?$_shot(?: and save(?: it)?)?(?: (?:now|it|this))?\$");
  static final _retry = _re(r"^(?:try again|try that again|retry|one more time|do it again)$");

  // Loose mentions that deserve a question rather than a guess.
  static final _looseRec = _re(r"\b(?:screen ?record(?:ing|er)?|record(?:ing)? (?:my|the) screen)\b");
  static final _looseShot = _re("\\b${_shot}s?\\b");
  static final _notACommand = _re(
      r"^(?:search|find|look up|look for|google|download|install|get me|tell me|what|how|why|who|when|where|is|are|does|do|can i|should i)\b");

  /// Result: a [CaptureCommand], a [CaptureClarification], or null (not a capture request).
  static Object? match(String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 160) return null;

    if (_retry.hasMatch(t)) return lastFailed == null ? null : const CaptureCommand(CaptureIntent.retry);
    if (_explain.hasMatch(t)) return const CaptureCommand(CaptureIntent.explain);
    if (_status.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingStatus);
    if (_storage.hasMatch(t)) return const CaptureCommand(CaptureIntent.storage);
    if (_audioModes.hasMatch(t)) return const CaptureCommand(CaptureIntent.audioModes);
    if (_options.hasMatch(t)) return const CaptureCommand(CaptureIntent.options);

    if (_setResolutionAuto.hasMatch(t)) return const CaptureCommand(CaptureIntent.setResolution, {'value': 'auto'});
    final res = _setResolution.firstMatch(t);
    if (res != null) return CaptureCommand(CaptureIntent.setResolution, {'value': res.group(1)!});
    final ori = _setOrientation.firstMatch(t);
    if (ori != null) return CaptureCommand(CaptureIntent.setOrientation, {'value': ori.group(1) ?? ori.group(2)!});
    if (_audioOn.hasMatch(t)) return const CaptureCommand(CaptureIntent.setAudio, {'value': 'mic'});
    if (_audioOff.hasMatch(t)) return const CaptureCommand(CaptureIntent.setAudio, {'value': 'none'});
    if (_audioDevice.hasMatch(t)) return const CaptureCommand(CaptureIntent.setAudio, {'value': 'device'});
    if (_openSettings.hasMatch(t)) return const CaptureCommand(CaptureIntent.openSettings);

    if (_controls.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingControls);
    if (_cancel.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingCancel);
    if (_pause.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingPause);
    if (_resume.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingResume);
    if (_stop.hasMatch(t)) return const CaptureCommand(CaptureIntent.recordingStop);
    for (final re in _start) {
      final m = re.firstMatch(t);
      if (m != null) return CaptureCommand(CaptureIntent.recordingStart, {'audio': _audioFrom(m.group(1) ?? '')});
    }

    final edit = _editLatest.hasMatch(t);
    if (edit) return const CaptureCommand(CaptureIntent.editLatest, {'kind': 'screenshot'});
    final share = _shareLatest.firstMatch(t);
    if (share != null) return CaptureCommand(CaptureIntent.shareLatest, {'kind': _kindOf(share.group(1)!)});
    final latest = _previewLatest.firstMatch(t);
    if (latest != null) return CaptureCommand(CaptureIntent.previewLatest, {'kind': _kindOf(latest.group(1)!)});
    final lib = _library.firstMatch(t);
    if (lib != null) return CaptureCommand(CaptureIntent.openLibrary, {'kind': _kindOf(lib.group(1)!)});
    if (_studio.hasMatch(t)) return const CaptureCommand(CaptureIntent.openStudio);

    if (_fullPage.hasMatch(t)) return const CaptureCommand(CaptureIntent.screenshotFullPage);
    if (_webpage.hasMatch(t)) return const CaptureCommand(CaptureIntent.screenshotWebpage);
    if (_fullScreen.hasMatch(t)) return const CaptureCommand(CaptureIntent.screenshotFullScreen);
    if (_auto.hasMatch(t)) return const CaptureCommand(CaptureIntent.screenshotAuto);

    // Mentions screen recording / screenshots but in a way we can't read reliably.
    final words = t.split(' ').length;
    if (words > 8 || _notACommand.hasMatch(t)) return null;
    if (_looseRec.hasMatch(t)) {
      return const CaptureClarification('Do you want me to start a screen recording, or open your recordings?',
          ['Start screen recording', 'Open my recordings', 'Show capture options']);
    }
    if (_looseShot.hasMatch(t)) {
      return const CaptureClarification('Should I take a screenshot of this page, or of your whole screen?',
          ['Screenshot this page', 'Capture my screen', 'Open my screenshots']);
    }
    return null;
  }

  static String _kindOf(String word) {
    if (word.contains('shot') || word.contains('grab') || word.contains('snapshot') || word.contains('screenshot')) {
      return 'screenshot';
    }
    if (word.contains('record') || word.contains('video') || word.contains('cast')) return 'recording';
    return 'any';
  }

  static String _audioFrom(String rest) {
    final r = rest.trim();
    if (r.isEmpty) return 'default';
    if (RegExp(r'\b(?:without|no)\b.*\b(?:audio|sound|microphone|mic|voice)\b|\b(?:silent(?:ly)?|muted?)\b').hasMatch(r)) {
      return 'none';
    }
    final mic = RegExp(r'\b(?:microphone|mic|my voice|voice|narration|narrating)\b').hasMatch(r);
    final device = RegExp(r'\b(?:app|apps|device|internal|system|phone|game) (?:sound|audio)\b').hasMatch(r);
    if (mic && device) return 'mic_device';
    if (device) return 'device';
    if (mic || RegExp(r'\bwith (?:the )?(?:audio|sound)\b').hasMatch(r)) return 'mic';
    return 'default';
  }
}
