// test/security/shield_engine_test.dart
//
// NOVA Shield blocking on Android (3.13.0): the same decisions as the PC
// engine — list domains and their subdomains, third-party only, paused
// sites, and the Password Guard upload lock.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/shield/engine/shield_engine.dart';

void main() {
  final shield = NovaShieldEngine.instance;

  setUp(() {
    shield.testEnabled = true;
    shield.useRulesForTest({'doubleclick.net': 'a', 'google-analytics.com': 't', 'coinhive.com': 'm', 'tracker.example.org': 't'});
    shield.paused.clear();
  });

  test('site of a host', () {
    expect(shieldSiteOf('www.news.example.co.uk'), 'example.co.uk');
    expect(shieldSiteOf('shop.example.com'), 'example.com');
    expect(shieldSiteOf('example.com'), 'example.com');
    expect(shieldSiteOf('203.0.113.9'), '203.0.113.9');
  });

  test('list domains and their subdomains are matched', () {
    expect(shield.matchHost('securepubads.g.doubleclick.net'), 'doubleclick.net');
    expect(shield.matchHost('doubleclick.net'), 'doubleclick.net');
    expect(shield.matchHost('notdoubleclick.net'), isNull);
    expect(shield.matchHost('cdn.jsdelivr.net'), isNull);
  });

  test('third-party requests only, never the site itself', () {
    final e = shield.check('https://securepubads.g.doubleclick.net/tag/js/gpt.js', 'https://news.example.com/a');
    expect(e, isNotNull);
    expect(e!.category, 'a');
    expect(e.rule, 'doubleclick.net');
    // A site's own requests are never blocked, even when its domain is listed.
    expect(shield.check('https://tracker.example.org/x.js', 'https://www.example.org/'), isNull);
    expect(shield.check('https://tracker.example.org/x.js', 'https://news.example.com/'), isNotNull);
    expect(shield.check('https://cdn.jsdelivr.net/npm/x.js', 'https://news.example.com/'), isNull);
  });

  test('nothing is blocked when the blocker is off or the site is paused', () async {
    shield.testEnabled = false;
    expect(shield.check('https://doubleclick.net/x', 'https://news.example.com/'), isNull);
    shield.testEnabled = true;
    shield.paused.add('example.com');
    expect(shield.check('https://doubleclick.net/x', 'https://news.example.com/'), isNull);
    expect(shield.check('https://doubleclick.net/x', 'https://other.org/'), isNotNull);
  });

  test('blocked requests are counted per page', () {
    const tab = 42;
    shield.pageStarted(tab, 'https://news.example.com/');
    final before = shield.lifetimeTotal;
    shield.record(tab, shield.check('https://www.google-analytics.com/g/collect', 'https://news.example.com/')!);
    shield.record(tab, shield.check('https://doubleclick.net/ad.gif', 'https://news.example.com/', type: 'image')!);
    final c = shield.countsFor(tab);
    expect(c.total, 2);
    expect(c.byCategory, {'t': 1, 'a': 1});
    expect(c.uniqueHosts, 2);
    expect(shield.lifetimeTotal, before + 2);
    shield.pageStarted(tab, 'https://news.example.com/next');
    expect(shield.countsFor(tab).total, 0);
    shield.forgetTab(tab);
  });

  test('Password Guard lock refuses uploads from that tab only', () {
    shield.lockPosts(7, true);
    expect(shield.refusedUpload(7, 'POST'), isTrue);
    expect(shield.refusedUpload(7, 'put'), isTrue);
    expect(shield.refusedUpload(7, 'GET'), isFalse);
    expect(shield.refusedUpload(8, 'POST'), isFalse);
    shield.lockPosts(7, false);
    expect(shield.refusedUpload(7, 'POST'), isFalse);
  });
}
