import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_proxy_resolver/native_proxy_resolver.dart';
import 'package:sableen/download_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Downloads use the fallback route returned by WPAD', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channel = MethodChannelNativeProxyResolver.methodChannel;
    SystemProxy.resolver = SystemProxyResolver(
      platform: MethodChannelNativeProxyResolver(),
      invalidateOnChange: false,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      SystemProxy.resolver = SystemProxyResolver();
    });
    final queue = DownloadQueue();
    final uri = Uri.parse('https://example.org/episode.mp4');
    Future<String> resolve(Map<String, Object> reply) {
      SystemProxy.clearCache();
      messenger.setMockMethodCallHandler(channel, (_) async => reply);
      return queue.route(uri);
    }

    final missed = {
      'source': 'autoDetect',
      'error': 'WPAD found no PAC script',
    };
    expect(await resolve(missed), 'DIRECT');
    expect(
      await resolve({
        ...missed,
        'source': 'manual',
        'proxyList': 'proxy.example:8080',
      }),
      'PROXY proxy.example:8080',
    );
    await expectLater(
      resolve({
        ...missed,
        'source': 'pac',
        'pacUrl': 'https://example.org/proxy.pac',
      }),
      throwsA(isA<HttpException>()),
    );
  });
}
