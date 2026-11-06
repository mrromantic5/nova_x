// lib/features/playback/playback_session.dart
//
// AI Playback (3.12.0): what happens when ▶ is tapped in the browser.
//   1. Free plan: 10 plays per 24 hours (Premium: unlimited).
//   2. First time only: a short notice that the page's text is sent to
//      NOVA AI to write the conversation.
//   3. Read the page on the phone (not on pages with password/card fields).
//   4. Pick the phone's voices for the page's language.
//   5. NOVA AI writes the conversation; the phone's voices speak it.
// The same page again (same text) replays without asking NOVA AI again and
// without counting another play.

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../premium/screens/subscription_screen.dart';
import 'playback_api.dart';
import 'playback_engine.dart';
import 'playback_models.dart';
import 'playback_page_reader.dart';
import 'playback_quota.dart';

class PlaybackSession {
  PlaybackSession._();

  static const _consentKey = 'nx_playback_notice_seen';

  // Last few conversations made in this app session: replays are free.
  static final Map<String, PlaybackScript> _recent = {};

  static String _keyFor(PageSnapshot p, String lang) =>
      '$lang|${p.url}|${p.text.length}|${p.text.hashCode}';

  /// Starts AI Playback for the page in [c]. Returns the engine (already
  /// "preparing") for the player, or null when nothing should play.
  static Future<PlaybackEngine?> start(BuildContext context, InAppWebViewController c, String url) async {
    final page = await PlaybackPageReader.read(c, url);
    if (!context.mounted) return null;
    if (page == null || !page.playable) {
      _toast(context,
          page?.sensitive == true ? 'AI Playback is off on pages with password or card fields.' : 'This page doesn’t have enough text for AI Playback.');
      return null;
    }

    final lang0 = page.lang.isEmpty ? 'en' : page.lang;
    final cachedKey = _recent.keys.where((k) => k.endsWith('|${page.url}|${page.text.length}|${page.text.hashCode}')).firstOrNull;

    if (cachedKey == null) {
      final left = await PlaybackQuota.left();
      if (!context.mounted) return null;
      if (left != null && left <= 0) {
        await _limitReached(context);
        return null;
      }
      if (!await _notice(context)) return null;
      if (!context.mounted) return null;
    }

    final engine = PlaybackEngine();
    _run(engine, page, lang0, cachedKey);
    return engine;
  }

  static Future<void> _run(PlaybackEngine engine, PageSnapshot page, String lang0, String? cachedKey) async {
    final api = PlaybackApi();
    try {
      final lang = await engine.prepare(lang0);
      final key = _keyFor(page, lang);
      var script = _recent[key] ?? (cachedKey != null ? _recent[cachedKey] : null);
      if (script == null) {
        // The intro plays while NOVA AI writes the conversation: no silent wait.
        engine.startIntro();
        script = await api.script(page, lang: lang);
        await PlaybackQuota.recordUse();
        _recent[key] = script;
        if (_recent.length > 12) _recent.remove(_recent.keys.first);
      }
      engine.start(script);
    } on PlaybackException catch (e) {
      engine.fail(e.message);
    } catch (_) {
      engine.fail('AI Playback couldn’t start. Please try again.');
    } finally {
      api.dispose();
    }
  }

  /// One-time notice. Returns false when the user cancels.
  static Future<bool> _notice(BuildContext context) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_consentKey) == true) return true;
      if (!context.mounted) return false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.podcasts_rounded, color: AppTheme.accentCyan),
            const SizedBox(width: 10),
            Text('NOVA AI Playback', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          content: Text(
            'Ava and Leo, your NOVA AI hosts, talk you through this page: what it offers and how it can help you.\n\n'
            'NOVA AI uses this page’s content to create the conversation. Nothing is saved to your account.\n\n'
            'Not available in private tabs or on pages with password or payment fields. '
            'Free plan: ${PlaybackQuota.freeLimit} plays a day · Premium: unlimited.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Play')),
          ],
        ),
      );
      if (ok == true) await p.setBool(_consentKey, true);
      return ok == true;
    } catch (_) {
      return true; // storage trouble: don't block (the notice shows next time)
    }
  }

  static Future<void> _limitReached(BuildContext context) async {
    final next = await PlaybackQuota.nextFreeAt();
    if (!context.mounted) return;
    final wait = next == null ? '' : ' The next free play is at ${TimeOfDay.fromDateTime(next).format(context)}.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Daily NOVA AI Playback limit reached', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(
          'You’ve used your ${PlaybackQuota.freeLimit} free NOVA AI Playbacks for today.$wait\n\nNOVA X Premium gives you unlimited NOVA AI Playback.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
            },
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: const Text('Get Premium'),
          ),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
