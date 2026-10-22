// lib/features/network/services/network_intents.dart
//
// What NOVA understands about the connection and the phone (pure Dart,
// unit-tested). Checked before NOVA's other commands, so these questions are
// answered with real measurements instead of an AI guess:
//
//   "Hey NOVA, what's my internet speed?"     → speedTest (runs a real test)
//   "how fast is my wifi" / "run a speed test" → speedTest
//   "what's my ping" / "check my latency"      → ping (latency only, ~2 s)
//   "what's my IP address"                      → ip
//   "what's my battery percentage"              → battery
//   "open NOVA Network"                          → open (handled as an app screen)

enum NetworkIntent { none, speedTest, ping, ip, battery, open }

class NetworkIntents {
  NetworkIntents._();

  static String _clean(String text) => text
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"^\s*(?:hey|hi|hello|ok|okay)\s+nova\b[\s,]*"), '')
      .replaceAll(RegExp(r'[?!.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final RegExp _open = RegExp(
      r"^(?:please\s+)?(?:open|show|launch|go to|start)\s+(?:the\s+)?(?:nova\s+network|network\s+(?:page|tools|tester|test)|speed\s*test(?:er)?\s+page)$");

  static final RegExp _speed = RegExp(
      r"\b(?:(?:internet|network|net|wi-?fi|wireless|data|mobile data|connection|broadband|download|upload|line|5g|4g|lte)\s+speeds?"
      r"|speed\s*test|test\s+(?:my\s+|the\s+)?(?:internet|network|connection|wi-?fi|speed|data)"
      r"|check\s+(?:my\s+|the\s+)?(?:internet|network|connection|wi-?fi)(?:\s+speed)?"
      r"|how\s+(?:fast|good|strong|quick)\s+is\s+(?:my\s+|the\s+|this\s+)?(?:internet|network|connection|wi-?fi|data|line)"
      r"|(?:is\s+)?(?:my\s+)?(?:internet|wi-?fi|connection|network)\s+(?:is\s+)?(?:so\s+|very\s+|too\s+)?(?:slow|fast)"
      r"|how\s+(?:many\s+)?(?:mbps|megabits))\b");

  static final RegExp _ping = RegExp(
      r"\b(?:what(?:'s|\s+is)\s+my\s+(?:ping|latency)|check\s+(?:my\s+)?(?:ping|latency)|(?:my\s+)?ping\s+test|test\s+(?:my\s+)?(?:ping|latency)|how\s+(?:high|low|good)\s+is\s+my\s+(?:ping|latency))\b");

  static final RegExp _ip = RegExp(
      r"\b(?:what(?:'s|\s+is)\s+my\s+(?:public\s+)?ip(?:\s+address)?|my\s+(?:public\s+)?ip\s+address|show\s+(?:me\s+)?my\s+ip|tell\s+me\s+my\s+ip)\b");

  static final RegExp _battery = RegExp(
      r"\b(?:battery\s+(?:level|percentage|percent|status|left|remaining)|how\s+much\s+(?:battery|charge)|what(?:'s|\s+is)\s+my\s+battery|is\s+my\s+(?:phone|battery)\s+charging|check\s+my\s+battery)\b");

  static NetworkIntent parse(String text) {
    final t = _clean(text);
    if (t.isEmpty) return NetworkIntent.none;
    if (_open.hasMatch(t)) return NetworkIntent.open;
    // Requests for something else that just mention speed ("search internet speed tips").
    if (RegExp(r'^(?:search|google|look up|find|play|open)\b').hasMatch(t)) return NetworkIntent.none;
    if (_ping.hasMatch(t)) return NetworkIntent.ping;
    if (_speed.hasMatch(t)) return NetworkIntent.speedTest;
    if (_ip.hasMatch(t)) return NetworkIntent.ip;
    if (_battery.hasMatch(t)) return NetworkIntent.battery;
    return NetworkIntent.none;
  }
}
