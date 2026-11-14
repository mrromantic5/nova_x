// test/guide/guide_cosmetic_test.dart (3.13.0, ported from NOVA X for PC)
//
// Feature Guide integrity and NOVA Shield page clean-up rule parsing.
// (The page surveyor itself is tested in Chromium.)

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:nova_x/features/guide/guide_content.dart';
import 'package:nova_x/features/shield/engine/shield_cosmetic.dart';

void main() {
  group('Feature Guide', () {
    test('ids are unique and every section is filled in', () {
      final ids = kGuide.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final s in kGuide) {
        expect(s.title.trim(), isNotEmpty, reason: s.id);
        expect(s.summary.length, greaterThan(30), reason: s.id);
        expect(GuideCategory.order, contains(s.category), reason: s.id);
      }
    });

    test('every Read more link in the app points to a real section', () {
      // Scans the Android sources for ReadMoreLink('id') and guide: 'id'.
      final ids = <String>{};
      final re = RegExp(r"""(?:ReadMoreLink\(\s*|ReadMoreLink\.open\(\s*context,\s*|guide:\s*)'([a-z_]+)'""");
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          ids.add(m.group(1)!);
        }
      }
      expect(ids, isNotEmpty);
      for (final id in ids) {
        expect(guideSection(id), isNotNull, reason: 'missing guide section "$id"');
      }
    });

    test('PC-only sections are not in the Android guide', () {
      for (final id in ['sidebar', 'memory_saver', 'command_palette', 'pc_integration', 'theme', 'studio', 'containers', 'recon', 'api_studio']) {
        expect(guideSection(id), isNull, reason: id);
      }
      final all = kGuide.map((s) => s.searchText).join(' ');
      for (final pcOnly in ['ctrl+', 'windows hello', 'file explorer', 'powershell', 'the tray']) {
        expect(all, isNot(contains(pcOnly)), reason: pcOnly);
      }
    });

    test('the links used next to features exist', () {
      for (final id in [
        'shield', 'page_cleanup', 'site_controls', 'fingerprint', 'password_guard',
        'download_verdict', 'session_shield', 'shield_dns', 'self_test', 'security_center',
        'open_safely', 'scam_explainer', 'security_lens', 'site_xray', 'rewrite_rules',
        'nova_agent', 'cyber', 'assistant', 'voice_calls', 'map',
      ]) {
        expect(guideSection(id), isNotNull, reason: id);
      }
    });

    test('search text covers the content', () {
      expect(guideSection('password_guard')!.searchText, contains('phishing'));
    });
  });

  group('Page clean-up rules', () {
    const list = '''
! comment
###AD_160
##.sponsored-ad
##div[data-ad="1"]
example.com##.site-banner
shop.example.com,other.org##.promo-box
example.com#@#.sponsored-ad
example.*##.any-tld
~skip.com##.negated
example.com#?#.procedural:has-text(Ad)
||ads.example.net^
''';

    test('splits generic rules for the surveyor', () {
      final r = CosmeticRules.parse(list);
      expect(r.ids, {'AD_160'});
      expect(r.classes, {'sponsored-ad'});
      expect(r.complex, ['div[data-ad="1"]']);
    });

    test('site rules and exceptions apply to the site and its subdomains', () {
      final r = CosmeticRules.parse(list);
      final shop = r.forHost('shop.example.com');
      expect(shop.hide, containsAll(['.site-banner', '.promo-box', '.any-tld']));
      expect(shop.except, contains('.sponsored-ad'));
      expect(r.forHost('other.org').hide, ['.promo-box']);
      expect(r.forHost('unrelated.net').hide, isEmpty);
    });

    test('procedural, negated and network rules are skipped', () {
      final r = CosmeticRules.parse(list);
      final all = [...r.complex, ...r.specific.values.expand((l) => l)];
      expect(all.any((s) => s.contains('has-text')), isFalse);
      expect(r.specific.containsKey('~skip.com'), isFalse);
      expect(all.any((s) => s.contains('ads.example.net')), isFalse);
    });

    test('surveyor script carries the data', () {
      final js = ShieldCosmetic.surveyorSource(CosmeticRules.parse(list).surveyorData());
      expect(js, contains('AD_160'));
      expect(js, isNot(contains('__DATA__')));
      final cfg = ShieldCosmetic.siteConfigScript(off: false, hide: ['.x'], except: []);
      expect(cfg, contains('__novaCosApply'));
    });
  });
}
