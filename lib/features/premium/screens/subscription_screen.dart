// lib/features/premium/screens/subscription_screen.dart
//
// NOVA X Premium — golden, SaaS-grade subscription screen.
//   • Country select (Ghana / Nigeria; other countries choose Ghana)
//   • Monthly / 6-Month plans with per-country pricing
//   • Paystack checkout in a WebView (verify-on-demand, no webhook)
//   • Premium receipt popup on success; Renew when expired

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/subscription_service.dart';

const Color _gold = Color(0xFFFFC83D);
const Color _goldDeep = Color(0xFFE8A317);

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  SubStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String _country = 'GH';
  String _plan = 'sixmonth';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SubscriptionService.fetchStatus();
    if (!mounted) return;
    setState(() {
      _status = s;
      if (s.lastCountry != null && SubscriptionService.countries.containsKey(s.lastCountry)) {
        _country = s.lastCountry!;
      }
      _loading = false;
    });
  }

  String _money(String plan, String country) {
    final cur = SubscriptionService.countries[country]!['currency']!;
    final amt = SubscriptionService.priceFor(plan, country);
    return '$cur $amt';
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    final init = await SubscriptionService.init(_plan, _country);
    if (!mounted) return;
    if (!init.success || init.authorizationUrl == null) {
      setState(() => _busy = false);
      _snack(init.message.isNotEmpty ? init.message : 'Could not start payment', error: true);
      return;
    }
    final reference = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => _PaystackPayScreen(url: init.authorizationUrl!)),
    );
    if (!mounted) return;
    if (reference == null || reference.isEmpty) {
      setState(() => _busy = false);
      _snack('Payment cancelled');
      return;
    }
    // Verify with the server
    final v = await SubscriptionService.verify(reference);
    if (!mounted) return;
    setState(() => _busy = false);
    if (v.active) {
      await _load();
      if (mounted) _showReceipt(v.receipt);
    } else {
      _snack(v.message.isNotEmpty ? v.message : 'Payment not confirmed yet', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
      backgroundColor: error ? AppTheme.danger : AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Receipt popup ──────────────────────────────────────────────────────────
  void _showReceipt(Map<String, dynamic> r) {
    final plan = (r['plan_label'] ?? r['plan'] ?? '').toString();
    final amount = '${r['currency'] ?? ''} ${r['amount'] ?? ''}';
    final ref = (r['reference'] ?? '').toString();
    final expires = (r['expires_at'] ?? '').toString();
    final exp = expires.length >= 10 ? expires.substring(0, 10) : expires;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withOpacity(0.4)),
            boxShadow: [BoxShadow(color: _gold.withOpacity(0.18), blurRadius: 40, spreadRadius: 2)],
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [_gold, _goldDeep]),
                boxShadow: [BoxShadow(color: _gold.withOpacity(0.5), blurRadius: 24)],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 16),
            Text('Payment Successful', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Welcome to NOVA X Premium', style: GoogleFonts.inter(color: _gold, fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgDark, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _rcptRow('Plan', plan),
                _rcptRow('Amount', amount),
                _rcptRow('Active until', exp),
                _rcptRow('Reference', ref, mono: true),
              ]),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold, foregroundColor: const Color(0xFF1A1300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Done', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _rcptRow(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5)),
          const Spacer(),
          Flexible(child: Text(v, textAlign: TextAlign.right,
              style: (mono ? GoogleFonts.jetBrainsMono : GoogleFonts.inter)(
                  color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      );

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final active = _status?.active == true;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark, elevation: 0,
        title: Text('NOVA Premium', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
              child: active ? _activeView() : _plansView(),
            ),
    );
  }

  Widget _crown() => Container(
        width: 78, height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [_gold, _goldDeep]),
          boxShadow: [BoxShadow(color: _gold.withOpacity(0.45), blurRadius: 30, spreadRadius: 1)],
        ),
        child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 44),
      );

  Widget _activeView() {
    final exp = _status?.expiresAt;
    final expStr = exp == null ? '' : '${exp.year}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')}';
    final planLabel = SubscriptionService.plans[_status?.plan]?['label']?.toString() ?? (_status?.plan ?? '');
    return Column(children: [
      const SizedBox(height: 18),
      _crown(),
      const SizedBox(height: 16),
      Text('You\'re Premium', style: GoogleFonts.spaceGrotesk(
          color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('All NOVA X features are unlocked', style: GoogleFonts.inter(color: _gold, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 24),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_gold.withOpacity(0.14), _goldDeep.withOpacity(0.06)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          _kv('Plan', planLabel),
          const Divider(color: AppTheme.glassBorder, height: 22),
          _kv('Renews / expires', expStr),
          const Divider(color: AppTheme.glassBorder, height: 22),
          _kv('Status', 'Active'),
        ]),
      ),
      const SizedBox(height: 18),
      Text('When your subscription expires, daily reward tasks switch back on and your saved points are still there.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5, height: 1.5)),
      const SizedBox(height: 22),
      _payButton(label: 'Extend / Renew'),
    ]);
  }

  Widget _kv(String k, String v) => Row(children: [
        Text(k, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5)),
        const Spacer(),
        Text(v, style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      ]);

  Widget _plansView() {
    final expired = _status?.lastPlan != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Center(child: _crown()),
      const SizedBox(height: 16),
      Center(child: Text('Go Premium', style: GoogleFonts.spaceGrotesk(
          color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800))),
      const SizedBox(height: 6),
      Center(child: Text('Unlock every NOVA X feature — no points, no limits',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5))),
      const SizedBox(height: 22),

      // Benefits
      _benefit('All premium features unlocked instantly'),
      _benefit('NOVA Shield, Cyber, Map, DevTools & more'),
      _benefit('Save projects & files in the Code Editor'),
      _benefit('Premium badge on your profile'),
      const SizedBox(height: 24),

      // Country
      Text('COUNTRY', style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      Row(children: [
        _countryChip('GH'),
        const SizedBox(width: 10),
        _countryChip('NG'),
      ]),
      const SizedBox(height: 6),
      Text('Other countries: select Ghana 🇬🇭', style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
      const SizedBox(height: 22),

      // Plans
      Text('CHOOSE A PLAN', style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      _planCard('monthly', 'Monthly', null),
      const SizedBox(height: 12),
      _planCard('sixmonth', '6 Months', 'BEST VALUE'),
      const SizedBox(height: 26),

      _payButton(label: expired ? 'Renew Premium' : 'Subscribe Now'),
      const SizedBox(height: 12),
      Center(child: Text('Secured by Paystack · Mobile Money & Card',
          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5))),
    ]);
  }

  Widget _benefit(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 22, height: 22,
              decoration: BoxDecoration(color: _gold.withOpacity(0.15), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: _gold, size: 15)),
          const SizedBox(width: 12),
          Expanded(child: Text(t, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5))),
        ]),
      );

  Widget _countryChip(String code) {
    final c = SubscriptionService.countries[code]!;
    final sel = _country == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _country = code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: sel ? _gold.withOpacity(0.14) : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? _gold : AppTheme.glassBorder, width: sel ? 1.5 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(c['flag']!, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(c['name']!, style: GoogleFonts.inter(
                color: sel ? _gold : AppTheme.textSecondary, fontSize: 14,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Widget _planCard(String plan, String label, String? tag) {
    final sel = _plan == plan;
    final price = _money(plan, _country);
    final usd = SubscriptionService.plans[plan]!['usd'];
    final perMonth = plan == 'sixmonth';
    return GestureDetector(
      onTap: () => setState(() => _plan = plan),
      child: Container(
        decoration: BoxDecoration(
          gradient: sel
              ? LinearGradient(colors: [_gold.withOpacity(0.16), _goldDeep.withOpacity(0.05)])
              : null,
          color: sel ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sel ? _gold : AppTheme.glassBorder, width: sel ? 1.6 : 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: sel ? _gold : AppTheme.textHint, width: 2),
              color: sel ? _gold : Colors.transparent,
            ),
            child: sel ? const Icon(Icons.check_rounded, color: Color(0xFF1A1300), size: 16) : null,
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              if (tag != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(6)),
                  child: Text(tag, style: GoogleFonts.inter(
                      color: const Color(0xFF1A1300), fontSize: 9.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text('≈ \$$usd${perMonth ? '  ·  6 months' : '  ·  per month'}',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
          ]),
          const Spacer(),
          Text(price, style: GoogleFonts.spaceGrotesk(
              color: sel ? _gold : AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _payButton({required String label}) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _subscribe,
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold, foregroundColor: const Color(0xFF1A1300),
            disabledBackgroundColor: _gold.withOpacity(0.4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _busy
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF1A1300)))
              : Text(label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Paystack checkout (WebView). Pops the reference string on completion.
// ─────────────────────────────────────────────────────────────────────────────
class _PaystackPayScreen extends StatefulWidget {
  final String url;
  const _PaystackPayScreen({required this.url});
  @override
  State<_PaystackPayScreen> createState() => _PaystackPayScreenState();
}

class _PaystackPayScreenState extends State<_PaystackPayScreen> {
  bool _loading = true;
  bool _done = false;

  void _finish(String? reference) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, reference);
  }

  String? _refFrom(String url) {
    if (!url.contains('action=callback')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return uri.queryParameters['reference'] ?? uri.queryParameters['trxref'];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark, elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Row(children: [
          const Icon(Icons.lock_rounded, color: _gold, size: 16),
          const SizedBox(width: 8),
          Text('Secure Payment', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _finish(null),
        ),
      ),
      body: Stack(children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          ),
          onLoadStart: (c, url) {
            final ref = _refFrom(url?.toString() ?? '');
            if (ref != null) _finish(ref);
          },
          onLoadStop: (c, url) {
            if (mounted) setState(() => _loading = false);
            final ref = _refFrom(url?.toString() ?? '');
            if (ref != null) _finish(ref);
          },
        ),
        if (_loading)
          Container(color: AppTheme.bgDark,
              child: const Center(child: CircularProgressIndicator(color: _gold))),
      ]),
    );
  }
}
