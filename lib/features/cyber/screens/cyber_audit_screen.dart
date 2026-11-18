// lib/features/cyber/screens/cyber_audit_screen.dart
//
// NOVA Cyber — Audit & rules (3.14.0, ported from NOVA X for Windows).
//
//   Audit trail   a tamper-evident record of every scan, export, triage and
//                 monitoring change on this phone (each entry stores the
//                 SHA-256 of the one before it) with "Verify chain"
//   Rule packs    versioned JSON packs that add code-scan rules without
//                 updating NOVA X: import a .json, save the example, remove
//
// Everything stays on the phone.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/cyber_audit.dart';
import '../engine/cyber_code_scan.dart' show codeRules;
import '../engine/cyber_rulepacks.dart';
import '../engine/cyber_storage.dart';
import '../ui/cyber_palette.dart';
import '../ui/cyber_widgets.dart';

class CyberAuditScreen extends StatefulWidget {
  const CyberAuditScreen({super.key});

  @override
  State<CyberAuditScreen> createState() => _CyberAuditScreenState();
}

class _CyberAuditScreenState extends State<CyberAuditScreen> {
  AuditCheck? _check;
  bool _checking = false;
  List<AuditEntry> _entries = const [];
  List<RulePack> _packs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await CyberStorage.init();
    final entries = await CyberAudit.recent(limit: 200);
    final packs = await RulePacks.reload();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _packs = packs;
      _loading = false;
    });
    await _verify();
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final c = await CyberAudit.verify();
    if (mounted) {
      setState(() {
        _check = c;
        _checking = false;
      });
    }
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a rule pack (.json)',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final f = res?.files.single;
      if (f == null || f.bytes == null) return;
      if (f.bytes!.length > 512 * 1024) {
        _snack('Rule packs are limited to 512 KB.');
        return;
      }
      final pack = await RulePacks.import(utf8.decode(f.bytes!, allowMalformed: true));
      await CyberAudit.log('rules.import', pack.name, detail: '${pack.version} · ${pack.rules.length} rules');
      _snack('Rule pack "${pack.name}" added (${pack.rules.length} rules${pack.errors.isEmpty ? '' : ', ${pack.errors.length} skipped'}).');
      await _load();
    } on FormatException catch (e) {
      _snack('Not a valid rule pack: ${e.message}');
    } catch (e) {
      _snack('Couldn\'t import the rule pack: $e');
    }
  }

  Future<void> _saveExample() async {
    try {
      final text = await RulePacks.exampleJson();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save example rule pack',
        fileName: 'example-team-rules.json',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (path != null) _snack('Example saved — edit it, then import it here.');
    } catch (e) {
      _snack('Couldn\'t save the example: $e');
    }
  }

  Future<void> _remove(RulePack pk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${pk.name}"?'),
        content: const Text('Its rules stop running in code scans.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await RulePacks.remove(pk);
    await CyberAudit.log('rules.remove', pk.name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.textMuted),
            title: Text('Audit & rules', style: p.ui(size: 16, weight: FontWeight.w800)),
            actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: Icon(Icons.refresh_rounded, color: p.textMuted))],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    Text('A tamper-evident record of every scan on this phone, and the rule packs that extend the code scan.',
                        style: p.ui(size: 13, color: p.textMuted, height: 1.4)),
                    const SizedBox(height: 16),
                    _auditPanel(p),
                    const SizedBox(height: 16),
                    _packsPanel(p),
                  ]),
                ),
        );
      }),
    );
  }

  Widget _auditPanel(NovaPalette p) {
    final c = _check;
    return Panel(
      title: 'Audit trail',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(c == null ? Icons.hourglass_empty_rounded : c.intact ? Icons.verified_rounded : Icons.gpp_bad_rounded,
              color: c == null ? p.textFaint : c.intact ? p.success : p.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(c == null ? 'Checking…' : c.intact ? 'Chain intact — ${c.reason}' : 'Chain broken — ${c.reason}',
                style: p.ui(size: 13, weight: FontWeight.w600, color: c != null && !c.intact ? p.danger : p.text)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Each entry stores the SHA-256 of the one before it, so editing or deleting a line is detected.',
            style: p.ui(size: 12, color: p.textFaint)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _checking ? null : _verify,
            icon: _checking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded, size: 16),
            label: const Text('Verify chain'),
          ),
        ),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Text('Scans you run are recorded here.', style: p.ui(size: 12.5, color: p.textMuted))
        else
          for (final e in _entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${e.seq}', style: kMono.copyWith(fontSize: 11.5, color: p.textFaint)),
                  const SizedBox(width: 8),
                  Text(e.action, style: kMono.copyWith(fontSize: 11.5, color: p.accent, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(e.at.toLocal().toString().substring(0, 16), style: p.ui(size: 11.5, color: p.textFaint)),
                ]),
                const SizedBox(height: 2),
                Text('${e.target}${e.scope.isEmpty ? '' : '  ·  ${e.scope}'}${e.detail.isEmpty ? '' : '  ·  ${e.detail}'}',
                    style: p.ui(size: 12.5, color: p.text), maxLines: 3, overflow: TextOverflow.ellipsis),
              ]),
            ),
      ]),
    );
  }

  Widget _packsPanel(NovaPalette p) {
    return Panel(
      title: 'Rule packs',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Versioned JSON packs add code-scan rules without updating NOVA X. ${codeRules.length} built-in rules are always on. '
            'Rule ids become pack.<name>.<id>.', style: p.ui(size: 12.5, color: p.textMuted, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Import rule pack')),
          OutlinedButton.icon(onPressed: _saveExample, icon: const Icon(Icons.note_add_outlined, size: 18), label: const Text('Write example')),
        ]),
        const SizedBox(height: 12),
        if (_packs.isEmpty) Text('No packs installed.', style: p.ui(size: 12.5, color: p.textFaint)),
        for (final pk in _packs)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(pk.errors.isEmpty ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    size: 16, color: pk.errors.isEmpty ? p.success : p.warning),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pk.name}  ${pk.version}', style: p.ui(size: 13.5, weight: FontWeight.w700)),
                  Text('${pk.rules.length} rules · ${pk.file}', style: p.ui(size: 12, color: p.textFaint)),
                  for (final e in pk.errors.take(6)) Padding(padding: const EdgeInsets.only(top: 2), child: Text(e, style: p.ui(size: 12, color: p.warning))),
                ]),
              ),
              IconButton(tooltip: 'Remove', onPressed: () => _remove(pk), icon: Icon(Icons.delete_outline_rounded, color: p.textFaint)),
            ]),
          ),
      ]),
    );
  }
}
