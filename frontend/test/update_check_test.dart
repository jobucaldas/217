import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/updates/update_check.dart';

const _installed = '0.26.0101-1';
const _newer = '0.26.0201-1';

Map<String, dynamic> _release(
  String tag, {
  bool draft = false,
  String apkUrl = '',
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'assets': [
        {
          'name': 'checksums.txt',
          'browser_download_url': 'https://github.com/jobucaldas/217/releases/download/$tag/checksums.txt',
        },
        {
          'name': 'app-release.apk',
          'browser_download_url': apkUrl.isEmpty
              ? 'https://github.com/jobucaldas/217/releases/download/$tag/app-release.apk'
              : apkUrl,
        },
      ],
    };

http.Client _clientFor(List<Map<String, dynamic>> releases, {int status = 200}) =>
    MockClient((request) async {
      expect(request.url.host, 'api.github.com');
      expect(request.headers['Accept'], 'application/vnd.github+json');
      return http.Response(jsonEncode(releases), status);
    });

void main() {
  test('offers a newer release with its APK', () async {
    final update = await checkForUpdate(
      client: _clientFor([_release(_installed), _release(_newer)]),
      installed: _installed,
    );
    expect(update, isNotNull);
    expect(update!.tag, _newer);
    expect(
      update.apkUrl.toString(),
      'https://github.com/jobucaldas/217/releases/download/$_newer/app-release.apk',
    );
  });

  test('same or older release is not offered', () async {
    expect(
      await checkForUpdate(
        client: _clientFor([_release(_installed)]),
        installed: _installed,
      ),
      isNull,
    );
    expect(
      await checkForUpdate(
        client: _clientFor([_release(_installed)]),
        installed: _newer,
      ),
      isNull,
    );
  });

  test('nightly, drafts and malformed tags are ignored', () async {
    const draftTag = '0.26.0301-1';
    final update = await checkForUpdate(
      client: _clientFor([
        _release('nightly'),
        _release(draftTag, draft: true),
        _release('0.26.0401'),
        _release('v1.2.3'),
        _release(_newer),
      ]),
      installed: _installed,
    );
    expect(update?.tag, _newer);

    expect(
      await checkForUpdate(
        client: _clientFor([_release('nightly'), _release(draftTag, draft: true)]),
        installed: _installed,
      ),
      isNull,
    );
  });

  test('APK from a foreign host is rejected', () async {
    final update = await checkForUpdate(
      client: _clientFor([
        _release(_newer, apkUrl: 'https://evil.example.com/app-release.apk'),
      ]),
      installed: _installed,
    );
    expect(update, isNull);

    final insecure = await checkForUpdate(
      client: _clientFor([
        _release(
          _newer,
          apkUrl:
              'http://github.com/jobucaldas/217/releases/download/$_newer/app-release.apk',
        ),
      ]),
      installed: _installed,
    );
    expect(insecure, isNull);
  });

  test('network errors and bad responses read as no update', () async {
    final offline = MockClient((_) async => throw http.ClientException('offline'));
    expect(await checkForUpdate(client: offline, installed: _installed), isNull);

    final failing = _clientFor([_release(_newer)], status: 500);
    expect(await checkForUpdate(client: failing, installed: _installed), isNull);
  });

  test('dev builds without a version never offer updates', () async {
    final client = _clientFor([_release(_newer)]);
    expect(await checkForUpdate(client: client, installed: ''), isNull);
    expect(await checkForUpdate(client: client), isNull);
  });

  test('orders by date, then by run number (10 is after 9)', () async {
    final update = await checkForUpdate(
      client: _clientFor([_release('0.26.1101-9'), _release('0.26.1101-10')]),
      installed: '0.26.1101-2',
    );
    expect(update!.tag, '0.26.1101-10');
    expect(
      await checkForUpdate(
        client: _clientFor([_release('0.26.1101-10')]),
        installed: '0.26.1102-1',
      ),
      isNull,
    );
  });

  test('a legacy-tagged build is offered the new scheme', () async {
    final update = await checkForUpdate(
      client: _clientFor([_release('20261101172537_0c7b925'), _release('0.26.1101-1')]),
      installed: '20261101172537_0c7b925',
    );
    expect(update!.tag, '0.26.1101-1');
  });
}
