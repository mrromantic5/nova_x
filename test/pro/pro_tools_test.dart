// test/pro/pro_tools_test.dart (3.13.0, ported from NOVA X for PC: Recon
// Notebook and API Studio aren't part of the Android app)

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/pro/nova_agent.dart';
import 'package:nova_x/features/pro/open_safely.dart';
import 'package:nova_x/features/pro/page_rules.dart';
import 'package:nova_x/features/pro/pro_ui.dart';
import 'package:nova_x/features/pro/scam_check.dart';
import 'package:nova_x/features/pro/security_lens.dart';
import 'package:nova_x/features/pro/site_xray.dart';

void main() {
  group('helpers', () {
    test('base domain', () {
      expect(proBaseDomain('a.b.example.com'), 'example.com');
      expect(proBaseDomain('shop.example.co.uk'), 'example.co.uk');
      expect(proBaseDomain('mtn.com.gh'), 'mtn.com.gh');
      expect(proBaseDomain('192.168.1.10'), '192.168.1.10');
    });

    test('wildcards', () {
      expect(proWildcard('*.example.com').hasMatch('a.example.com'), isTrue);
      expect(proWildcard('*.example.com').hasMatch('example.org'), isFalse);
    });

    test('JS strings are escaped', () {
      expect(proJsString("it's\n</script>"), r"'it\'s\n<\/script>'");
    });
  });

  group('Rewrite Rules', () {
    final r = PageRules.instance;

    test('redirect with captures', () {
      expect(PageRules.applyRedirect('https://www.reddit.com/*', r'https://old.reddit.com/$1', 'https://www.reddit.com/r/flutter'),
          'https://old.reddit.com/r/flutter');
      expect(PageRules.applyRedirect('https://www.reddit.com/*', r'https://old.reddit.com/$1', 'https://example.com/'), isNull);
    });

    test('rules from JSON; disabled rules are ignored', () {
      r.decode('{"lowData":true,"lowDataFonts":false,"annoyances":true,"rules":['
          '{"type":"redirect","pattern":"https://a.com/*","value":"https://b.com/\$1"},'
          '{"type":"redirect","pattern":"https://c.com/*","value":"https://d.com/","enabled":false},'
          '{"type":"block","pattern":"*://*.ads.test/*"},'
          '{"type":"css","pattern":"*.site.com","value":".x{display:none}"},'
          '{"type":"bogus","pattern":"x"}]}');
      expect(r.rules.length, 4);
      expect(r.redirectFor('https://a.com/page?q=1'), 'https://b.com/page?q=1');
      expect(r.redirectFor('https://c.com/x'), isNull);
      final blocked = r.blockedPatterns();
      expect(blocked, contains('*://*.ads.test/*'));
      expect(blocked, contains('*.jpg'));
      expect(blocked, isNot(contains('*.woff2')));
      expect(r.cssFor('www.site.com').length, 1);
      expect(r.cssFor('site.com').length, 1);
      expect(r.cssFor('othersite.com'), isEmpty);
      expect(r.annoyances, isTrue);
      // encode → decode keeps everything
      final again = r.encode();
      r.decode(again);
      expect(r.encode(), again);
      r.decode(null);
      expect(r.rules, isEmpty);
    });

    test('site patterns', () {
      expect(PageRules.hostMatches('example.com', 'www.example.com'), isTrue);
      expect(PageRules.hostMatches('example.com', 'shop.example.com'), isFalse);
      expect(PageRules.hostMatches('*.example.com', 'shop.example.com'), isTrue);
      expect(PageRules.hostMatches('*', 'anything.org'), isTrue);
    });

    test('annoyance script switches autoplay handling', () {
      expect(PageRules.annoyanceJs(stopAutoplay: true), contains("querySelectorAll('video')"));
      expect(PageRules.annoyanceJs(stopAutoplay: false), isNot(contains("querySelectorAll('video')")));
    });
  });

  group('Scam Explainer', () {
    test('look-alike brand is flagged', () {
      final r = ScamAnalyzer.analyzeUrl('https://paypal-account-verify.top/login');
      expect(r.any((x) => x.title.contains('Paypal')), isTrue);
      expect(ScamVerdict(r).score, greaterThanOrEqualTo(55));
    });

    test('typo-squats are flagged', () {
      expect(ScamAnalyzer.analyzeUrl('https://www.amazonn.com/').any((x) => x.level == ProLevel.critical), isTrue);
    });

    test('the real site is not', () {
      expect(ScamAnalyzer.analyzeUrl('https://www.paypal.com/signin'), isEmpty);
      expect(ScamAnalyzer.analyzeUrl('https://mail.google.com/'), isEmpty);
    });

    test('short brand names only match whole words', () {
      expect(ScamAnalyzer.analyzeUrl('https://startups.com/').any((x) => x.level == ProLevel.critical), isFalse);
      expect(ScamAnalyzer.analyzeUrl('https://ups-delivery-fee.com/').any((x) => x.level == ProLevel.critical), isTrue);
    });

    test('address tricks', () {
      expect(ScamAnalyzer.analyzeUrl('http://example.com/').any((x) => x.title.contains('secure')), isTrue);
      expect(ScamAnalyzer.analyzeUrl('https://xn--pypal-4ve.com/').any((x) => x.level == ProLevel.high), isTrue);
      expect(ScamAnalyzer.analyzeUrl('https://203.0.113.5/login').any((x) => x.level == ProLevel.high), isTrue);
    });

    test('page signals', () {
      final s = ScamPageSignals.fromJson({
        'title': 'Congratulations! You have won',
        'text': 'Your account will be suspended within 24 hours. Pay a small delivery fee with a gift card. '
            'Send to bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
        'hasPassword': true,
        'formHosts': ['collect.evil.test'],
        'countdown': true,
      });
      final r = ScamAnalyzer.analyzePage(s, 'shop.example.com');
      final titles = r.map((x) => x.title).toList();
      expect(titles, contains('Promises prizes or easy money'));
      expect(titles, contains('Asks for unusual payment'));
      expect(titles, contains('Pressure to act fast'));
      expect(titles, contains('Shows a crypto wallet address'));
      expect(titles, contains('Your details go to another site'));
      expect(ScamVerdict(r).label, 'Likely scam');
    });

    test('AI prompt stays short', () {
      final v = ScamVerdict(ScamAnalyzer.analyzeUrl('https://paypal-login.top/'));
      expect(ScamAnalyzer.aiPrompt('https://paypal-login.top/', 'x', v, 'y' * 10000).length, lessThanOrEqualTo(3800));
    });
  });

  test('Site Data X-ray knows tracker companies', () {
    expect(SiteXray.kindOf('www.google-analytics.com'), TrackerKind.analytics);
    expect(SiteXray.kindOf('securepubads.g.doubleclick.net'), TrackerKind.ads);
    expect(SiteXray.kindOf('static.hotjar.com'), TrackerKind.replay);
    expect(SiteXray.kindOf('cdnjs.cloudflare.com'), TrackerKind.cdn);
    expect(SiteXray.kindOf('api.example.org'), TrackerKind.other);
  });

  group('Security Lens', () {
    test('missing headers lower the grade', () {
      final issues = SecurityLens.evaluate(url: 'https://example.com/', headers: {'Server': 'Apache/2.4.1'});
      final titles = issues.map((i) => i.title).join('|');
      expect(titles, contains('No HSTS'));
      expect(titles, contains('No Content-Security-Policy'));
      expect(titles, contains('framed'));
      expect(titles, contains('Server version'));
      final r = LensReport(url: 'https://example.com/', issues: issues, headers: const {});
      expect(r.score, lessThan(65));
    });

    test('a well-configured site gets an A', () {
      final issues = SecurityLens.evaluate(url: 'https://example.com/', headers: {
        'strict-transport-security': 'max-age=31536000; includeSubDomains',
        'content-security-policy': "default-src 'self'; frame-ancestors 'none'",
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'strict-origin-when-cross-origin',
        'permissions-policy': 'camera=()',
      });
      expect(LensReport(url: 'https://example.com/', issues: issues, headers: const {}).grade, 'A');
    });

    test('plain HTTP and weak cookies', () {
      final issues = SecurityLens.evaluate(
        url: 'http://example.com/',
        headers: const {},
        cookies: const [LensCookie('PHPSESSID')],
        page: const LensPage(insecureForms: 1, jquery: '1.12.4'),
      );
      final titles = issues.map((i) => i.title).join('|');
      expect(titles, contains('not served over HTTPS'));
      expect(titles, contains('readable by scripts'));
      expect(titles, contains('Old jQuery'));
      expect(issues.first.level, ProLevel.critical);
    });

    test('expired certificate', () {
      final now = DateTime(2026, 6, 1);
      final issues = SecurityLens.evaluate(
        url: 'https://example.com/',
        headers: const {},
        cert: LensCert(subject: 'CN=example.com', issuer: 'CN=CA', from: DateTime(2025), until: DateTime(2026, 5, 1)),
        now: now,
      );
      expect(issues.any((i) => i.title == 'Certificate has expired'), isTrue);
    });

    test('report as Markdown', () {
      final r = LensReport(url: 'https://example.com/', issues: SecurityLens.evaluate(url: 'https://example.com/', headers: const {}), headers: const {'server': 'x'});
      final md = r.toMarkdown();
      expect(md, startsWith('# Security Lens report'));
      expect(md, contains('## Findings'));
    });
  });

  test('link expander resolves relative redirects', () {
    expect(LinkExpander.nextUrl('https://t.co/abc', '/x?y=1'), 'https://t.co/x?y=1');
    expect(LinkExpander.nextUrl('https://t.co/abc', 'https://example.com/'), 'https://example.com/');
    expect(LinkExpander.nextUrl('https://t.co/abc', null), isNull);
  });

  group('Safe NOVA Agent', () {
    test('reads NOVA AI replies', () {
      final a = AgentAction.parse('Sure!\n```json\n{"thought":"open it","action":"click","id":"4"}\n```')!;
      expect(a.kind, AgentKind.click);
      expect(a.id, 4);
      expect(AgentAction.parse('no json here'), isNull);
      expect(AgentAction.parse('{"action":"hack"}'), isNull);
    });

    test('risky steps', () {
      final el = AgentElement.fromJson({'id': 1, 'tag': 'button', 'text': 'Place order'});
      expect(const AgentAction(AgentKind.click, id: 1).risky(el), isTrue);
      final ok = AgentElement.fromJson({'id': 2, 'tag': 'a', 'text': 'Contact us'});
      expect(const AgentAction(AgentKind.click, id: 2).risky(ok), isFalse);
    });

    test('prompt fits the AI limit and marks private fields', () {
      final s = AgentSnapshot.fromJson({
        'url': 'https://shop.test',
        'title': 'Shop',
        'text': 'x' * 5000,
        'els': [
          {'id': 1, 'tag': 'input', 'type': 'password', 'text': 'Password', 'sensitive': true, 'inView': true},
          for (var i = 2; i < 200; i++) {'id': i, 'tag': 'a', 'text': 'Link number $i with a long label', 'inView': true},
        ],
      });
      final prompt = agentPrompt('Find the cheapest item', s, ['Click “Shop” → ok']);
      expect(prompt.length, lessThanOrEqualTo(4000));
      expect(prompt, contains('(PRIVATE FIELD)'));
      expect(prompt, contains('GOAL: Find the cheapest item'));
    });
  });
}
