// lib/features/cyber/ui/cyber_verify.dart
//
// NOVA Cyber — "Verify you own this site" wizard and the verified-sites list.
// Android (3.13.0): same flow and wording as NOVA X for PC, phone layout.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/cyber_api.dart';
import 'cyber_palette.dart';
import 'cyber_widgets.dart';

/// Opens the wizard. Returns true when the site was verified.
Future<bool> showVerifyWizard(BuildContext context, {String host = ''}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => NovaThemed(child: _VerifyWizard(initialHost: host)),
  );
  return ok == true;
}

class _VerifyWizard extends StatefulWidget {
  const _VerifyWizard({required this.initialHost});
  final String initialHost;
  @override
  State<_VerifyWizard> createState() => _VerifyWizardState();
}

class _VerifyWizardState extends State<_VerifyWizard> {
  late final TextEditingController _host = TextEditingController(text: widget.initialHost);
  Challenge? _challenge;
  String _method = 'dns';
  bool _busy = false;
  String? _error;
  String? _status;
  bool _verified = false;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _getCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _challenge = await CyberApi.challenge(_host.text.trim());
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _check() async {
    final c = _challenge;
    if (c == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final (ok, msg) = await CyberApi.verify(c.host, _method);
      _verified = ok;
      _status = msg;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveFile() async {
    final c = _challenge;
    if (c == null) return;
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save verification file',
        fileName: 'nova-x-verify.txt',
        bytes: Uint8List.fromList(utf8.encode('${c.token}\n')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t save the file: $e');
      return;
    }
    if (path == null) return;
    if (mounted) setState(() => _status = 'Saved. Upload it so it opens at https://${c.host}/.well-known/nova-x-verify.txt');
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = _challenge;
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.verified_user_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text('Verify site ownership', style: p.title(size: 18))),
              IconButton(onPressed: () => Navigator.pop(context, _verified), icon: Icon(Icons.close_rounded, color: p.textMuted)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Full scans send active security tests, so they only run on sites you control. '
              'You get a unique code; the NOVA X server checks it on your site and re-checks it before every full scan.',
              style: p.ui(size: 13, color: p.textMuted, height: 1.45),
            ),
            const SizedBox(height: 18),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _step(p, 1, 'Your site', Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _host,
                        enabled: c == null && !_busy,
                        onSubmitted: (_) => _getCode(),
                        style: p.ui(size: 14),
                        decoration: InputDecoration(
                          hintText: 'example.com',
                          isDense: true,
                          prefixIcon: Icon(Icons.public_rounded, size: 18, color: p.textFaint),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (c == null)
                      FilledButton(onPressed: _busy ? null : _getCode, child: const Text('Get my code'))
                    else
                      TextButton(onPressed: _busy ? null : () => setState(() => _challenge = null), child: const Text('Change')),
                  ])),
                  if (c != null) ...[
                    _step(
                      p,
                      2,
                      'Add the code to your site — choose one way',
                      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'dns', label: Text('DNS'), icon: Icon(Icons.dns_outlined, size: 16)),
                            ButtonSegment(value: 'file', label: Text('File'), icon: Icon(Icons.upload_file_outlined, size: 16)),
                            ButtonSegment(value: 'meta', label: Text('Tag'), icon: Icon(Icons.code_rounded, size: 16)),
                          ],
                          showSelectedIcon: false,
                          selected: {_method},
                          onSelectionChanged: (s) => setState(() {
                            _method = s.first;
                            _status = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        _instructions(p, c),
                      ]),
                    ),
                    _step(
                      p,
                      3,
                      'Check',
                      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        FilledButton.icon(
                          onPressed: _busy || _verified ? null : _check,
                          icon: _busy
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.fact_check_outlined, size: 18),
                          label: Text(_verified ? 'Verified' : 'Check now'),
                        ),
                        if (c.expiresAt != null)
                          Text('Code valid until ${c.expiresAt!.toLocal().toString().substring(0, 16)}', style: p.ui(size: 12, color: p.textFaint)),
                      ]),
                    ),
                  ],
                  if (_status != null)
                    _banner(p, _status!, _verified ? p.success : p.warning, _verified ? Icons.verified_rounded : Icons.hourglass_bottom_rounded),
                  if (_error != null) _banner(p, _error!, p.danger, Icons.error_outline_rounded),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: Text('Verification lasts 30 days. Removing the code ends it at the next scan.',
                    style: p.ui(size: 11.5, color: p.textFaint)),
              ),
              if (_verified) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _instructions(NovaPalette p, Challenge c) {
    final m = c.methods[_method] ?? const {};
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(k, style: p.ui(size: 12, color: p.textMuted, weight: FontWeight.w600)))),
            Expanded(child: CodeBlock(v, maxHeight: 80)),
          ]),
        );
    switch (_method) {
      case 'dns':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('In your DNS provider (Cloudflare, Namecheap, cPanel Zone Editor…) add this record. It verifies ${m['covers'] ?? c.host}.',
              style: p.ui(size: 13, color: p.text, height: 1.45)),
          const SizedBox(height: 10),
          kv('Type', 'TXT'),
          kv('Name / Host', m['name'] ?? ''),
          kv('Value', m['value'] ?? c.token),
          Text('Some providers add the domain automatically — then enter only "_nova-x-verify". DNS can take a few minutes to update.',
              style: p.ui(size: 12, color: p.textFaint)),
        ]);
      case 'file':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Upload a text file so that it opens at the address below (HTTPS, no redirect). It verifies ${m['covers'] ?? c.host}.',
              style: p.ui(size: 13, color: p.text, height: 1.45)),
          const SizedBox(height: 10),
          kv('Address', m['url'] ?? ''),
          kv('Content', m['content'] ?? c.token),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _saveFile, icon: const Icon(Icons.download_rounded, size: 16), label: const Text('Save nova-x-verify.txt')),
          ),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Paste this tag inside <head> of your home page (${m['url'] ?? 'https://${c.host}/'}). It verifies ${m['covers'] ?? c.host}.',
              style: p.ui(size: 13, color: p.text, height: 1.45)),
          const SizedBox(height: 10),
          kv('Tag', m['tag'] ?? ''),
          Text('WordPress: Appearance › Theme File Editor › header.php, or a "header code" plugin.', style: p.ui(size: 12, color: p.textFaint)),
        ]);
    }
  }

  Widget _step(NovaPalette p, int n, String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
            child: Text('$n', style: p.ui(size: 12, weight: FontWeight.w700, color: p.accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.only(top: 3, bottom: 10), child: Text(title, style: p.ui(size: 13.5, weight: FontWeight.w700))),
              child,
            ]),
          ),
        ]),
      );

  Widget _banner(NovaPalette p, String text, Color c, IconData icon) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text, style: p.ui(size: 13, color: p.text, height: 1.4))),
        ]),
      );
}

/// Verified sites (from the server).
class VerifiedSitesView extends StatefulWidget {
  const VerifiedSitesView({super.key, required this.onScan});
  final void Function(String host) onScan;
  @override
  State<VerifiedSitesView> createState() => _VerifiedSitesViewState();
}

class _VerifiedSitesViewState extends State<VerifiedSitesView> {
  List<VerifiedSite>? _sites;
  int? _left;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (s, left) = await CyberApi.domains();
      _sites = s;
      _left = left;
    } catch (e) {
      _error = '$e';
      _sites = const [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
      Text('Verified sites', style: p.title(size: 20)),
      const SizedBox(height: 4),
      Text('Full scans run only on these sites. ${_left == null ? '' : '$_left full scans left today.'}', style: p.ui(size: 13, color: p.textMuted)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
          onPressed: () async {
            if (await showVerifyWizard(context)) _load();
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Verify a site'),
        ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 18)),
      ]),
      const SizedBox(height: 18),
      if (_error != null) Panel(child: Text(_error!, style: p.ui(color: p.danger))),
      if (_sites == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (_sites != null && _sites!.isEmpty && _error == null)
        Panel(
          child: Column(children: [
            Icon(Icons.verified_user_outlined, size: 36, color: p.textFaint),
            const SizedBox(height: 10),
            Text('No verified sites yet', style: p.ui(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Verify a site you own to unlock the full scan.', style: p.ui(size: 13, color: p.textMuted)),
          ]),
        ),
      for (final s in _sites ?? const <VerifiedSite>[])
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(s.expired ? Icons.gpp_maybe_outlined : Icons.verified_rounded, color: s.expired ? p.warning : p.success),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.scope == 'domain' ? '${s.host}  +  subdomains' : s.host, style: p.ui(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${const {'dns': 'DNS record', 'file': 'Verification file', 'meta': 'HTML tag'}[s.method] ?? s.method}'
                    '${s.expiresAt == null ? '' : '  ·  ${s.expired ? 'expired' : 'valid until'} ${s.expiresAt!.toLocal().toString().substring(0, 10)}'}',
                    style: p.ui(size: 12, color: p.textFaint),
                  ),
                ]),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () async {
                  try {
                    await CyberApi.revoke(s.host);
                  } catch (_) {}
                  _load();
                },
                icon: Icon(Icons.delete_outline_rounded, color: p.textMuted),
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: s.expired
                    ? TextButton(
                        onPressed: () async {
                          if (await showVerifyWizard(context, host: s.host)) _load();
                        },
                        child: const Text('Verify again'))
                    : FilledButton.tonal(onPressed: () => widget.onScan(s.host), child: const Text('Full scan')),
              ),
            ),
          ]),
        ),
    ]),
    );
  }
}
