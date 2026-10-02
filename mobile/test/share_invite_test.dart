import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/platform/share_sheet.dart';
import 'package:a217/src/screens/share_screens.dart';
import 'package:a217/src/theme/app_theme.dart';

const _owner = User(id: '1', email: 'her@example.com', name: 'Her');
const _openShare = ShareState(
  status: 'open',
  inviteCode: 'ABCD1234',
  inviteUrl: 'https://217.example.com/?invite=ABCD1234',
);

class _JoinApi extends ApiClient {
  _JoinApi() : super(AppConfig.fromEnvironment());

  String? accepted;

  @override
  Future<ShareState> acceptShare(String code) async {
    accepted = code;
    return const ShareState(status: 'active', canEditCalendar: false);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required ShareState share,
  Brightness brightness = Brightness.light,
  ApiClient? api,
  ValueChanged<ShareState>? onJoined,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildApp217Theme(
        brightness: brightness,
        palette: AppPalette.azure,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ShareSettingsSection(
            api: api ?? ApiClient(AppConfig.fromEnvironment()),
            strings: const Strings(AppLanguage.en),
            user: _owner,
            share: share,
            onShareChanged: (_) {},
            onJoined: onJoined,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> shareCalls;
  late String? clipboard;

  setUp(() {
    shareCalls = [];
    clipboard = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      intentsChannel,
      (call) async {
        shareCalls.add(call);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      intentsChannel,
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final brightness in Brightness.values) {
    testWidgets('open invite: send via share sheet, link and code ($brightness)',
        (tester) async {
      await _pump(tester, share: _openShare, brightness: brightness);

      expect(find.text('Send invite'), findsOneWidget);
      expect(find.text('https://217.example.com/?invite=ABCD1234'),
          findsOneWidget);
      expect(find.text('ABCD1234'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('share-send-invite')));
      await tester.pumpAndSettle();

      expect(shareCalls, hasLength(1));
      final args = shareCalls.single.arguments as Map;
      expect(shareCalls.single.method, 'shareText');
      expect(args['text'], contains('https://217.example.com/?invite=ABCD1234'));
      expect(args['text'], contains('ABCD1234'));
      expect(args['subject'], 'Invite to my 217 calendar');
    });
  }

  testWidgets('copy link and copy code confirm what was copied',
      (tester) async {
    await _pump(tester, share: _openShare);

    await tester.tap(find.byTooltip('Copy link'));
    await tester.pumpAndSettle();
    expect(clipboard, 'https://217.example.com/?invite=ABCD1234');
    expect(find.text('Link copied'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pumpAndSettle();
    expect(clipboard, 'ABCD1234');
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('send falls back to copying the link without a share sheet',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      intentsChannel,
      (call) async => throw PlatformException(code: 'no_activity'),
    );
    await _pump(tester, share: _openShare);

    await tester.tap(find.byKey(const ValueKey('share-send-invite')));
    await tester.pumpAndSettle();
    expect(clipboard, 'https://217.example.com/?invite=ABCD1234');
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('active share hides the used invite code', (tester) async {
    await _pump(
      tester,
      share: const ShareState(
        status: 'active',
        inviteCode: 'ABCD1234',
        partnerName: 'BF',
      ),
    );
    expect(find.text('Shared with BF'), findsOneWidget);
    expect(find.text('ABCD1234'), findsNothing);
    expect(find.text('Send invite'), findsNothing);
    expect(find.text('Revoke access'), findsOneWidget);
  });

  testWidgets('nothing shared: join someone else with a code', (tester) async {
    final api = _JoinApi();
    ShareState? joined;
    await _pump(
      tester,
      share: const ShareState(status: 'none'),
      api: api,
      onJoined: (share) => joined = share,
    );

    expect(find.text('Create invite'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-join-with-code')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('join-code-field')),
      ' abcd1234 ',
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(api.accepted, 'abcd1234');
    expect(joined?.isActive, isTrue);
  });
}
