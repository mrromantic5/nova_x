// lib/features/xcoder/widgets/xcoder_ui.dart
//
// Look of X Coder: a dark, VS Code-style workbench that matches NOVA X.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';

class XC {
  XC._();
  static const Color bg = Color(0xFF0B1424); // editor surround
  static const Color side = Color(0xFF0E1A2D); // explorer, panels
  static const Color bar = Color(0xFF0A1220); // title & tab strip
  static const Color tabActive = Color(0xFF13233B);
  static const Color border = Color(0xFF1B2B45);
  static const Color hover = Color(0xFF16263F);
  static const Color status = Color(0xFF1565C0);
  static const Color statusOffline = Color(0xFF37474F);
  static const Color accent = AppTheme.accentCyan;
  static const Color text = Color(0xFFD7E3F4);
  static const Color dim = Color(0xFF8DA2BF);
  static const Color faint = Color(0xFF5A7090);
  static const Color error = Color(0xFFFF5370);
  static const Color warning = Color(0xFFFFCB6B);
  static const Color info = Color(0xFF82AAFF);
  static const Color ok = Color(0xFFC3E88D);
  static const Color added = Color(0xFF1F3B2A);
  static const Color removed = Color(0xFF41202A);

  static TextStyle ui(double size, {Color color = text, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight);

  static TextStyle mono(double size, {Color color = text, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight, height: 1.35);
}

/// Colour + icon per file type for the explorer and tabs.
({IconData icon, Color color}) fileVisual(String name, {bool dir = false, bool open = false}) {
  if (dir) return (icon: open ? Icons.folder_open_rounded : Icons.folder_rounded, color: const Color(0xFF90A4C8));
  final lower = name.toLowerCase();
  final ext = lower.contains('.') ? lower.split('.').last : '';
  if (lower == 'readme.md') return (icon: Icons.info_outline_rounded, color: const Color(0xFF42A5F5));
  if (lower == 'package.json') return (icon: Icons.inventory_2_outlined, color: const Color(0xFF8BC34A));
  if (lower.startsWith('.git')) return (icon: Icons.account_tree_outlined, color: const Color(0xFFF4511E));
  if (lower == 'dockerfile') return (icon: Icons.directions_boat_outlined, color: const Color(0xFF0DB7ED));
  return switch (ext) {
    'html' || 'htm' => (icon: Icons.html_rounded, color: const Color(0xFFE44D26)),
    'css' || 'scss' || 'less' => (icon: Icons.css_rounded, color: const Color(0xFF42A5F5)),
    'js' || 'mjs' || 'cjs' || 'jsx' => (icon: Icons.javascript_rounded, color: const Color(0xFFF7DF1E)),
    'ts' || 'tsx' => (icon: Icons.code_rounded, color: const Color(0xFF3178C6)),
    'json' => (icon: Icons.data_object_rounded, color: const Color(0xFFCBCB41)),
    'dart' => (icon: Icons.flutter_dash_rounded, color: const Color(0xFF29B6F6)),
    'py' => (icon: Icons.code_rounded, color: const Color(0xFF3776AB)),
    'php' => (icon: Icons.php_rounded, color: const Color(0xFF8892BF)),
    'java' || 'kt' || 'kts' => (icon: Icons.coffee_rounded, color: const Color(0xFFE76F00)),
    'md' => (icon: Icons.notes_rounded, color: const Color(0xFF90CAF9)),
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' || 'ico' => (icon: Icons.image_outlined, color: const Color(0xFF26A69A)),
    'sh' || 'bash' => (icon: Icons.terminal_rounded, color: const Color(0xFF4EAA25)),
    'yml' || 'yaml' || 'toml' || 'ini' || 'env' => (icon: Icons.settings_outlined, color: const Color(0xFFB0BEC5)),
    'sql' => (icon: Icons.storage_rounded, color: const Color(0xFFE38C00)),
    'xml' => (icon: Icons.code_rounded, color: const Color(0xFFFF6600)),
    'zip' => (icon: Icons.folder_zip_outlined, color: const Color(0xFFB0BEC5)),
    _ => (icon: Icons.insert_drive_file_outlined, color: const Color(0xFF90A4C8)),
  };
}

/// Ace mode for a file name.
String aceModeFor(String name) {
  final lower = name.toLowerCase();
  if (lower == 'dockerfile') return 'dockerfile';
  if (lower == 'makefile') return 'makefile';
  if (lower == '.gitignore') return 'gitignore';
  final ext = lower.contains('.') ? lower.split('.').last : '';
  return switch (ext) {
    'html' || 'htm' => 'html',
    'css' => 'css',
    'scss' => 'scss',
    'less' => 'less',
    'js' || 'mjs' || 'cjs' => 'javascript',
    'jsx' => 'jsx',
    'ts' => 'typescript',
    'tsx' => 'tsx',
    'json' || 'webmanifest' => 'json',
    'json5' => 'json5',
    'dart' => 'dart',
    'py' => 'python',
    'java' => 'java',
    'kt' || 'kts' => 'kotlin',
    'php' => 'php',
    'c' || 'h' || 'cpp' || 'cc' || 'hpp' || 'cxx' => 'c_cpp',
    'cs' => 'csharp',
    'go' => 'golang',
    'rs' => 'rust',
    'rb' => 'ruby',
    'swift' => 'swift',
    'sql' => 'sql',
    'xml' || 'plist' => 'xml',
    'svg' => 'svg',
    'yml' || 'yaml' => 'yaml',
    'md' || 'markdown' => 'markdown',
    'sh' || 'bash' || 'zsh' => 'sh',
    'toml' => 'toml',
    'ini' || 'env' || 'properties' => 'ini',
    'lua' => 'lua',
    'pl' || 'pm' => 'perl',
    'r' => 'r',
    'scala' => 'scala',
    'hs' => 'haskell',
    'bat' || 'cmd' => 'batchfile',
    'ps1' => 'powershell',
    'diff' || 'patch' => 'diff',
    'vue' => 'vue',
    _ => 'text',
  };
}

/// Name shown for an Ace mode.
const Map<String, String> kAceModeLabels = {
  'html': 'HTML', 'css': 'CSS', 'scss': 'SCSS', 'less': 'Less', 'javascript': 'JavaScript', 'jsx': 'JSX',
  'typescript': 'TypeScript', 'tsx': 'TSX', 'json': 'JSON', 'json5': 'JSON5', 'dart': 'Dart', 'python': 'Python',
  'java': 'Java', 'kotlin': 'Kotlin', 'php': 'PHP', 'c_cpp': 'C / C++', 'csharp': 'C#', 'golang': 'Go', 'rust': 'Rust',
  'ruby': 'Ruby', 'swift': 'Swift', 'sql': 'SQL', 'mysql': 'MySQL', 'pgsql': 'PostgreSQL', 'xml': 'XML', 'svg': 'SVG',
  'yaml': 'YAML', 'markdown': 'Markdown', 'sh': 'Shell', 'toml': 'TOML', 'ini': 'INI', 'lua': 'Lua', 'perl': 'Perl',
  'r': 'R', 'scala': 'Scala', 'haskell': 'Haskell', 'batchfile': 'Batch', 'powershell': 'PowerShell', 'diff': 'Diff',
  'vue': 'Vue', 'dockerfile': 'Dockerfile', 'makefile': 'Makefile', 'gitignore': '.gitignore', 'graphqlschema': 'GraphQL',
  'text': 'Plain Text', 'plain_text': 'Plain Text',
};

/// Editor themes bundled with the app.
const Map<String, String> kAceThemes = {
  'one_dark': 'One Dark',
  'dracula': 'Dracula',
  'monokai': 'Monokai',
  'github_dark': 'GitHub Dark',
  'tomorrow_night': 'Tomorrow Night',
  'tomorrow_night_eighties': 'Tomorrow Night 80s',
  'nord_dark': 'Nord',
  'solarized_dark': 'Solarized Dark',
  'cloud9_night': 'Cloud9 Night',
  'cloud_editor_dark': 'Cloud Editor Dark',
  'gruvbox': 'Gruvbox',
  'twilight': 'Twilight',
  'github': 'GitHub Light',
  'cloud_editor': 'Cloud Editor Light',
  'chrome': 'Chrome Light',
};

/// Editor preferences (saved on the phone).
class XSettings {
  XSettings({
    this.theme = 'one_dark',
    this.fontSize = 13,
    this.tabSize = 2,
    this.softTabs = true,
    this.wrap = false,
    this.liveAutocomplete = true,
    this.lineNumbers = true,
    this.relativeNumbers = false,
    this.invisibles = false,
    this.autoSave = true,
    this.keyBar = true,
    this.formatOnSave = false,
  });

  String theme;
  double fontSize;
  int tabSize;
  bool softTabs;
  bool wrap;
  bool liveAutocomplete;
  bool lineNumbers;
  bool relativeNumbers;
  bool invisibles;
  bool autoSave;
  bool keyBar;
  bool formatOnSave;

  static const _key = 'xcoder_settings_v1';

  Map<String, Object?> toAce() => {
        'theme': theme,
        'fontSize': fontSize,
        'tabSize': tabSize,
        'softTabs': softTabs,
        'wrap': wrap,
        'live': liveAutocomplete,
        'lineNumbers': lineNumbers,
        'relative': relativeNumbers,
        'invisibles': invisibles,
      };

  Map<String, Object?> toJson() => {
        ...toAce(),
        'autoSave': autoSave,
        'keyBar': keyBar,
        'formatOnSave': formatOnSave,
      };

  static Future<XSettings> load() async {
    final s = XSettings();
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return s;
      final m = jsonDecode(raw);
      if (m is! Map) return s;
      if (m['theme'] is String && kAceThemes.containsKey(m['theme'])) s.theme = m['theme'] as String;
      if (m['fontSize'] is num) s.fontSize = (m['fontSize'] as num).clamp(9, 28).toDouble();
      if (m['tabSize'] is num) s.tabSize = (m['tabSize'] as num).clamp(1, 8).toInt();
      bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
      s.softTabs = b('softTabs', s.softTabs);
      s.wrap = b('wrap', s.wrap);
      s.liveAutocomplete = b('live', s.liveAutocomplete);
      s.lineNumbers = b('lineNumbers', s.lineNumbers);
      s.relativeNumbers = b('relative', s.relativeNumbers);
      s.invisibles = b('invisibles', s.invisibles);
      s.autoSave = b('autoSave', s.autoSave);
      s.keyBar = b('keyBar', s.keyBar);
      s.formatOnSave = b('formatOnSave', s.formatOnSave);
    } catch (_) {}
    return s;
  }

  Future<void> save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));
    } catch (_) {}
  }
}

void xToast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: XC.ui(13, color: Colors.white)),
    backgroundColor: error ? const Color(0xFF8E2433) : const Color(0xFF1B2B45),
    behavior: SnackBarBehavior.floating,
    duration: Duration(milliseconds: error ? 3500 : 2200),
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 34),
  ));
}

Future<String?> xPrompt(BuildContext context,
    {required String title, String initial = '', String hint = '', String action = 'OK', String? Function(String)? validate}) {
  final c = TextEditingController(text: initial);
  // Select the name without its extension, like VS Code.
  final dot = initial.lastIndexOf('.');
  c.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : initial.length);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: XC.side,
        title: Text(title, style: XC.ui(16, weight: FontWeight.w700)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: XC.mono(14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: XC.mono(14, color: XC.faint),
            errorText: error,
            filled: true,
            fillColor: XC.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) {
            final e = validate?.call(v);
            if (e != null) {
              set(() => error = e);
              return;
            }
            Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final e = validate?.call(c.text);
              if (e != null) {
                set(() => error = e);
                return;
              }
              Navigator.pop(ctx, c.text.trim());
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

Future<bool> xConfirm(BuildContext context, String title, String body, {String action = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: XC.side,
      title: Text(title, style: XC.ui(16, weight: FontWeight.w700)),
      content: Text(body, style: XC.ui(14, color: XC.dim)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: TextStyle(color: danger ? XC.error : XC.accent)),
        ),
      ],
    ),
  );
  return r == true;
}

class XIconBtn extends StatelessWidget {
  const XIconBtn(this.icon, {super.key, required this.tooltip, required this.onTap, this.color = XC.dim, this.size = 20, this.badge});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: size, color: onTap == null ? XC.faint : color),
            if (b != null)
              Positioned(
                right: 4,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: XC.error, borderRadius: BorderRadius.circular(8)),
                  child: Text(b, style: XC.ui(9, color: Colors.white, weight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
