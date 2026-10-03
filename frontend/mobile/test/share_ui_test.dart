import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/api/client.dart';
import 'package:a217/src/config.dart';
import 'package:a217/src/i18n.dart';
import 'package:a217/src/models.dart';
import 'package:a217/src/screens/share_screens.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('partner revoked screen offers code + delete ($brightness)',
        (tester) async {
      final api = ApiClient(AppConfig.fromEnvironment());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: brightness,
            palette: AppPalette.blue,
          ),
          home: PartnerJoinScreen(
            api: api,
            strings: const Strings(AppLanguage.en),
            revoked: true,
            onJoined: (_) {},
            onAccountDeleted: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You are not invited to her 217 calendar'),
        findsOneWidget,
      );
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      final scheme = Theme.of(
        tester.element(find.text('You are not invited to her 217 calendar')),
      ).colorScheme;
      final title = tester.widget<Text>(
        find.text('You are not invited to her 217 calendar'),
      );
      expect(title.style?.color, scheme.onSurface);
    });

    testWidgets('delete account warning dialog is readable ($brightness)',
        (tester) async {
      final api = ApiClient(AppConfig.fromEnvironment());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildApp217Theme(
            brightness: brightness,
            palette: AppPalette.blue,
          ),
          home: Scaffold(
            body: DeleteAccountSection(
              api: api,
              strings: const Strings(AppLanguage.en),
              onAccountDeleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This permanently deletes your data and login account. This cannot be undone.',
        ),
        findsOneWidget,
      );
      expect(find.text('Delete permanently'), findsOneWidget);
    });
  }

  test('share state defaults owner editable', () {
    const share = ShareState(status: 'none');
    expect(share.canEditCalendar, isTrue);
    expect(share.isNone, isTrue);
  });

  test('user role helpers', () {
    const owner = User(id: '1', email: 'a@b.c', name: 'A', role: 'owner');
    const partner = User(id: '2', email: 'b@b.c', name: 'B', role: 'partner');
    final fresh = User.fromJson({'id': '3', 'email': 'c@b.c', 'role': ''});
    expect(owner.isOwner, isTrue);
    expect(owner.isPartner, isFalse);
    expect(partner.isPartner, isTrue);
    expect(partner.isOwner, isFalse);
    expect(fresh.hasRole, isFalse);
    expect(fresh.isOwner, isFalse);
  });
}
