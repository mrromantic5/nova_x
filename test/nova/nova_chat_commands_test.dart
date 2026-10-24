// test/nova/nova_chat_commands_test.dart
//
// NOVA AI chat: typed NOVA commands run for real; questions still go to the AI.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/ai/services/nova_chat_commands.dart';
import 'package:nova_x/features/network/services/network_intents.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_command_parser.dart';

void main() {
  final commands = NovaChatCommands(
      parser: NovaCommandParser(clock: () => DateTime(2026, 10, 19, 14, 5)));

  String? kinds(String text) =>
      commands.actions(text)?.map((a) => a.type.name).join(',');

  test('measurements run, advice questions go to NOVA AI', () {
    const cases = {
      "Hey NOVA, what's my internet speed?": NetworkIntent.speedTest,
      'test my internet speed': NetworkIntent.speedTest,
      'how fast is my wifi': NetworkIntent.speedTest,
      "what's my ping": NetworkIntent.ping,
      'what is my ip address': NetworkIntent.ip,
      "what's my battery percentage": NetworkIntent.battery,
      'open nova network': NetworkIntent.open,
      'how do I make my wifi faster': NetworkIntent.none,
      'why is my internet so slow?': NetworkIntent.none,
      'how to improve my internet speed': NetworkIntent.none,
      'give me tips to boost my wifi speed': NetworkIntent.none,
      'write a poem': NetworkIntent.none,
    };
    cases.forEach((q, want) => expect(commands.network(q), want, reason: q));
  });

  test('commands that run in the chat', () {
    expect(kinds('open nova music'), 'openApp');
    expect(kinds('play me a song'), 'playMusic');
    expect(kinds('next song'), 'musicControl');
    expect(kinds('change the song'), 'musicControl');
    expect(kinds('open youtube and play essence'), 'searchInApp');
    expect(kinds('navigate to accra mall'), 'navigate');
  });

  test('everything else is left to NOVA AI', () {
    for (final q in [
      'call wendy', // calls stay with the voice assistant
      'search the web for cats',
      'write a poem about the sea',
      'explain how wifi works',
      '/image a cat',
      '',
    ]) {
      expect(commands.actions(q), isNull, reason: q);
    }
  });

  test('page ids', () {
    expect(NovaChatCommands.featureOf(commands.actions('open nova network')!.single), 'nova_network');
    expect(NovaChatCommands.featureOf(commands.actions('open nova ai')!.single), 'nova_ai');
    expect(NovaChatCommands.featureOf(const NovaAction(NovaActionType.openApp, {'app': 'youtube'})), isNull);
    expect(NovaChatCommands.featureOf(const NovaAction(NovaActionType.playMusic, {'query': ''})), isNull);
  });
}
