// lib/features/devtools/screens/code_editor_screen.dart
//
// 3.11.0: the code editor is now X Coder (lib/features/xcoder/). This file
// keeps the names other screens use — CodeEditorScreen, CodeLang, kLangs,
// CodeWorkspaceStore — and forwards to X Coder.

import 'package:flutter/material.dart';

import '../../xcoder/screens/xcoder_screen.dart';
import '../../xcoder/workspace/xcoder_workspace.dart';

class CodeLang {
  final String label;
  final String mode;
  final Color color;
  final String ext;
  const CodeLang(this.label, this.mode, this.color, this.ext);
}

const List<CodeLang> kLangs = [
  CodeLang('HTML',        'html',       Color(0xFFE44D26), 'html'),
  CodeLang('CSS',         'css',        Color(0xFF2965F1), 'css'),
  CodeLang('JavaScript',  'javascript', Color(0xFFF7DF1E), 'js'),
  CodeLang('TypeScript',  'typescript', Color(0xFF3178C6), 'ts'),
  CodeLang('JSON',        'json',       Color(0xFF8BC34A), 'json'),
  CodeLang('Dart',        'dart',       Color(0xFF0175C2), 'dart'),
  CodeLang('Python',      'python',     Color(0xFF3776AB), 'py'),
  CodeLang('Java',        'java',       Color(0xFFEA2D2E), 'java'),
  CodeLang('Kotlin',      'kotlin',     Color(0xFF7F52FF), 'kt'),
  CodeLang('PHP',         'php',        Color(0xFF777BB4), 'php'),
  CodeLang('C',           'c_cpp',      Color(0xFF5C6BC0), 'c'),
  CodeLang('C++',         'c_cpp',      Color(0xFF00599C), 'cpp'),
  CodeLang('C#',          'csharp',     Color(0xFF68217A), 'cs'),
  CodeLang('Go',          'golang',     Color(0xFF00ADD8), 'go'),
  CodeLang('Rust',        'rust',       Color(0xFFDEA584), 'rs'),
  CodeLang('Ruby',        'ruby',       Color(0xFFCC342D), 'rb'),
  CodeLang('Swift',       'swift',      Color(0xFFFA7343), 'swift'),
  CodeLang('SQL',         'sql',        Color(0xFFE38C00), 'sql'),
  CodeLang('XML',         'xml',        Color(0xFFFF6600), 'xml'),
  CodeLang('YAML',        'yaml',       Color(0xFFCB171E), 'yaml'),
  CodeLang('Markdown',    'markdown',   Color(0xFF42A5F5), 'md'),
  CodeLang('Shell',       'sh',         Color(0xFF4EAA25), 'sh'),
];

/// Adds a file to the most recent X Coder project (kept for older callers).
class CodeWorkspaceStore {
  static Future<void> addFile(String name, String content) async {
    final ws = XWorkspace.instance;
    var projects = await ws.projects();
    if (projects.isEmpty) projects = [await ws.create('My Workspace', template: XTemplate.empty)];
    final rel = XWorkspace.normalize(name);
    if (rel == null || rel.isEmpty) return;
    await ws.write(projects.first, rel, content);
  }
}

class CodeEditorScreen extends StatelessWidget {
  final String? initialUrl;
  final String? initialContent;
  final CodeLang? initialLang;
  final String initialFileName;

  /// Kept for compatibility: X Coder always works on saved projects.
  final bool sharedWorkspace;

  const CodeEditorScreen({
    super.key,
    this.initialUrl,
    this.initialContent,
    this.initialLang,
    this.initialFileName = 'index.html',
    this.sharedWorkspace = false,
  });

  @override
  Widget build(BuildContext context) => XCoderScreen(
        initialContent: initialContent,
        initialUrl: initialUrl,
        initialFileName: (initialContent != null || initialUrl != null) ? initialFileName : null,
        initialMode: initialLang?.mode,
      );
}
