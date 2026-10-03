import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/screens/dialog_actions.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'dialog buttons share one row, main action on the filled button '
        '($brightness)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildApp217ColorScheme(brightness).brightness == brightness
            ? ThemeData(colorScheme: buildApp217ColorScheme(brightness))
            : null,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cambiar a modo pareja'),
                  actions: [
                    DialogActionRow(
                      secondary: DialogLinkButton(
                        onPressed: () {},
                        label: 'Cancelar',
                      ),
                      primary: FilledButton(
                        onPressed: () {},
                        child: const Text('Cambiar a modo pareja'),
                      ),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final cancel = find.text('Cancelar');
      final go = find.byType(FilledButton);
      expect(
        (tester.getCenter(cancel).dy - tester.getCenter(go).dy).abs(),
        lessThan(1),
      );
      expect(
          tester.getSize(go).width, greaterThan(tester.getSize(cancel).width));
      final scheme = Theme.of(tester.element(cancel)).colorScheme;
      final style = tester.widget<Text>(cancel).style;
      expect(style?.color ?? scheme.error, scheme.error);
    });
  }
}
