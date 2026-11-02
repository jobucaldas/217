import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/settings_screen.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'settings advanced options + single language label ($brightness)',
      (tester) async {
        var language = AppLanguage.en;
        final api = ApiClient(AppConfig.fromEnvironment());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildApp217Theme(
              brightness: brightness,
              palette: AppPalette.blue,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => SettingsPage(
                api: api,
                strings: Strings(language),
                language: language,
                themeMode: ThemeMode.system,
                palette: AppPalette.blue,
                onLanguageChanged: (l) => setState(() => language = l),
                onThemeModeChanged: (_) {},
                onPaletteChanged: (_) {},
                onApiBaseChanged: () {},
                onLogout: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
        // Section label only — not duplicated as DropdownMenu floating label.
        expect(find.text('LANGUAGE'), findsOneWidget);
        expect(find.text('Language'), findsNothing);
        expect(find.byType(DropdownMenu<AppLanguage>), findsOneWidget);
        expect(find.byType(SegmentedButton<bool>), findsNothing);
        expect(find.text('English'), findsWidgets);
        await tester.scrollUntilVisible(find.text('Advanced options'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Advanced options'), findsOneWidget);
        expect(find.text('Show more'), findsNothing);
        expect(find.text('Self-hosted server URL'), findsNothing);
        expect(find.text('Test connection'), findsNothing);

        await tester.tap(find.text('Advanced options'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(find.text('Test connection'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Hide advanced options'), findsOneWidget);
        expect(find.text('Self-hosted server URL'), findsWidgets);
        expect(find.text('Test connection'), findsOneWidget);

        await tester.scrollUntilVisible(
            find.byType(DropdownMenu<AppLanguage>), -200,
            scrollable: find.byType(Scrollable).first);
        // Open language dropdown menu and pick Português.
        await tester.tap(find.byType(DropdownMenu<AppLanguage>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Português').last);
        await tester.pumpAndSettle();

        expect(find.text('Ajustes'), findsOneWidget);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        expect(find.text('IDIOMA'), findsOneWidget);
        expect(find.text('Idioma'), findsNothing);
        await tester.scrollUntilVisible(find.text('Ocultar opções avançadas'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Ocultar opções avançadas'), findsOneWidget);
        expect(find.text('Mostrar menos'), findsNothing);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownMenu<AppLanguage>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Español').last);
        await tester.pumpAndSettle();
        expect(find.text('Ajustes'), findsOneWidget);
        expect(find.text('IDIOMA'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Ocultar opciones avanzadas'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Ocultar opciones avanzadas'), findsOneWidget);
      },
    );
  }

  testWidgets('signed in: share, no server setting, privacy link, logout',
      (tester) async {
    final api = ApiClient(AppConfig.fromEnvironment());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(
          brightness: Brightness.light,
          palette: AppPalette.blue,
        ),
        home: SettingsPage(
          api: api,
          strings: const Strings(AppLanguage.en),
          language: AppLanguage.en,
          themeMode: ThemeMode.system,
          palette: AppPalette.blue,
          onLanguageChanged: (_) {},
          onThemeModeChanged: (_) {},
          onPaletteChanged: (_) {},
          onApiBaseChanged: () {},
          user: const User(
            id: '1',
            email: 'a@b.c',
            name: 'Owner',
            role: 'owner',
          ),
          share: const ShareState(status: 'none'),
          onShareChanged: (_) {},
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<double> absoluteTop(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final scrollPosition = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      return scrollPosition + tester.getTopLeft(finder).dy;
    }

    final shareTop =
        await absoluteTop(find.text('SHARE CALENDAR WITH PARTNER'));
    final privacyTop = await absoluteTop(find.text('Privacy notice'));
    final logoutTop = await absoluteTop(find.text('Log out'));
    // The server is chosen before sign-in, so it is not offered here.
    // Advanced options is last; signed in, it only holds the guide.
    final advancedTop = await absoluteTop(find.text('Advanced options'));
    expect(advancedTop, greaterThan(logoutTop));
    expect(find.text('Self-hosted server URL'), findsNothing);
    expect(privacyTop, greaterThan(shareTop));
    expect(logoutTop, greaterThan(privacyTop));
    // Download, delete and withdraw live on the server's privacy page.
    final privacy = find.byKey(const ValueKey('privacy-notice'));
    expect(privacy, findsOneWidget);
    expect(tester.widget<Text>(find.text('Privacy notice')).style?.decoration,
        TextDecoration.underline);
    expect(find.text('Download my data'), findsNothing);
    expect(find.text('Delete account'), findsNothing);

    final logoutLabel = tester.widget<Text>(find.text('Log out'));
    expect(logoutLabel.style?.color, const Color(0xFFEA580C));
  });

  testWidgets('a failed stage save resets the dropdown to the saved stage',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final saved = <String>[];
    final api = ApiClient(
      AppConfig.fromEnvironment(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/account/stage') {
          saved.add(request.body);
          return http.Response('{"error":"boom"}', 500);
        }
        return http.Response('{}', 404);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildApp217Theme(brightness: Brightness.light),
        home: SettingsPage(
          api: api,
          strings: const Strings(AppLanguage.en),
          language: AppLanguage.en,
          themeMode: ThemeMode.system,
          palette: AppPalette.blue,
          onLanguageChanged: (_) {},
          onThemeModeChanged: (_) {},
          onPaletteChanged: (_) {},
          onApiBaseChanged: () {},
          user: const User(
            id: '1',
            email: 'a@b.c',
            name: 'Owner',
            role: 'owner',
          ),
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stage = find.byKey(const ValueKey('stage-dropdown'));
    final field = find.descendant(of: stage, matching: find.byType(TextField));
    String shown() => tester.widget<TextField>(field).controller!.text;
    await tester.scrollUntilVisible(stage, 200,
        scrollable: find.byType(Scrollable).first);
    Future<void> pick(String label) async {
      await tester.ensureVisible(stage);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    expect(shown(), 'Cycling');
    await pick('Menopause');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(shown(), 'Cycling');
    // Still usable after the failure: a second choice is sent too.
    await pick('Perimenopause');
    expect(saved, ['{"stage":"menopause"}', '{"stage":"perimenopause"}']);
    expect(shown(), 'Cycling');
  });

  for (final role in ['owner', 'partner']) {
    testWidgets('Personal section saves the display name ($role)',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final sent = <String>[];
      final api = ApiClient(
        AppConfig.fromEnvironment(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/account/profile') {
            sent.add(request.body);
            return http.Response(
                '{"user":{"id":"1","email":"a@b.c","name":"Sign-in",'
                '"role":"$role","display_name":"Ana"}}',
                200);
          }
          return http.Response('{}', 404);
        }),
      );
      SessionSnapshot? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(brightness: Brightness.light),
          home: SettingsPage(
            api: api,
            strings: const Strings(AppLanguage.en),
            language: AppLanguage.en,
            themeMode: ThemeMode.system,
            palette: AppPalette.blue,
            onLanguageChanged: (_) {},
            onThemeModeChanged: (_) {},
            onPaletteChanged: (_) {},
            onApiBaseChanged: () {},
            user: User(id: '1', email: 'a@b.c', name: 'Sign-in', role: role),
            onLogout: () async {},
            onProfileChanged: (session) => saved = session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERSONAL'), findsOneWidget);
      // Birth month and stage are the owner's only.
      expect(find.byKey(const ValueKey('birth-date')),
          role == 'owner' ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('stage-dropdown')),
          role == 'owner' ? findsOneWidget : findsNothing);

      // Pre-filled with the effective name, no hint or helper text.
      expect(find.widgetWithText(TextField, 'Sign-in'), findsOneWidget);
      expect(find.textContaining('Shown to the other person'), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey('display-name')), '  Ana ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('display-name-save')));
      await tester.pumpAndSettle();
      expect(sent, ['{"display_name":"Ana"}']);
      expect(saved?.user?.displayName, 'Ana');
      expect(find.text('Display name saved.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Ana'), findsOneWidget);
    });
  }
}
