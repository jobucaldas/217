import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/screens/repeat_minutes_controller.dart';
import 'package:a217/src/screens/repeat_settings_section.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  test('validOrDefaultRepeatMinutes seeds 15 outside 1-120, else keeps it', () {
    expect(validOrDefaultRepeatMinutes(0), 15);
    expect(validOrDefaultRepeatMinutes(-5), 15);
    expect(validOrDefaultRepeatMinutes(121), 15);
    expect(validOrDefaultRepeatMinutes(1), 1);
    expect(validOrDefaultRepeatMinutes(45), 45);
    expect(validOrDefaultRepeatMinutes(120), 120);
  });

  group('RepeatMinutesController', () {
    test('onChanged sets an error outside 1-120 and clears pending', () {
      var flushed = <int>[];
      final controller = RepeatMinutesController(
        currentMinutes: () => 15,
        onFlush: flushed.add,
      );
      controller.onChanged('0', rangeErrorText: 'bad');
      expect(controller.error, 'bad');
      controller.onChanged('45', rangeErrorText: 'bad');
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('flush is a no-op when the value equals the current saved minutes',
        () {
      final flushed = <int>[];
      final controller = RepeatMinutesController(
        currentMinutes: () => 15,
        onFlush: flushed.add,
      );
      controller.onChanged('15', rangeErrorText: 'bad');
      controller.flush();
      expect(flushed, isEmpty);
      controller.dispose();
    });

    test('flush fires onFlush once for a changed, valid value', () {
      final flushed = <int>[];
      final controller = RepeatMinutesController(
        currentMinutes: () => 15,
        onFlush: flushed.add,
      );
      controller.onChanged('45', rangeErrorText: 'bad');
      controller.flush();
      expect(flushed, [45]);
      // Calling flush again without a new pending edit is a no-op.
      controller.flush();
      expect(flushed, [45]);
      controller.dispose();
    });

    test('resyncAfterFailedSave resets text when there is no newer edit', () {
      final controller = RepeatMinutesController(
        currentMinutes: () => 20,
        onFlush: (_) {},
      );
      controller.attach();
      controller.textController.text = '45';
      controller.error = 'bad';
      controller.resyncAfterFailedSave(45, 20);
      expect(controller.textController.text, '20');
      expect(controller.error, isNull);
      controller.dispose();
    });

    test(
        'resyncAfterFailedSave leaves the field alone when a newer edit is '
        'pending', () {
      final controller = RepeatMinutesController(
        currentMinutes: () => 20,
        onFlush: (_) {},
      );
      controller.attach();
      controller.textController.text = '60';
      controller.onChanged('60', rangeErrorText: 'bad'); // pending, not flushed
      controller.resyncAfterFailedSave(45, 20);
      expect(controller.textController.text, '60');
      controller.dispose();
    });

    test('cancelPending clears the timer, pending value and error', () {
      final controller = RepeatMinutesController(
        currentMinutes: () => 15,
        onFlush: (_) {},
      );
      controller.onChanged('0', rangeErrorText: 'bad');
      expect(controller.error, 'bad');
      controller.cancelPending();
      expect(controller.error, isNull);
      expect(controller.hasNewerUnflushedEdit(15), isFalse);
      controller.dispose();
    });
  });

  group('RepeatSettingsSection widget', () {
    late RepeatMinutesController controller;

    Widget host({
      required bool repeatEnabled,
      required bool parentEnabled,
      required bool saving,
      String helperText = 'helper',
    }) =>
        MaterialApp(
          theme: buildApp217Theme(brightness: Brightness.light),
          home: Scaffold(
            body: RepeatSettingsSection(
              toggleKey: const ValueKey('toggle'),
              fieldKey: const ValueKey('field'),
              switchTitle: 'Repeat',
              switchSubtitle: 'subtitle',
              everyLabel: 'Every',
              minutesUnit: 'minutes',
              helperText: helperText,
              repeatEnabled: repeatEnabled,
              parentEnabled: parentEnabled,
              saving: saving,
              controller: controller,
              onToggle: (_) {},
              onMinutesChanged: (_) {},
              onMinutesSubmitted: () {},
            ),
          ),
        );

    setUp(() {
      controller = RepeatMinutesController(
        currentMinutes: () => 15,
        onFlush: (_) {},
      )..attach();
    });

    tearDown(() => controller.dispose());

    testWidgets('field only renders while the repeat is enabled',
        (tester) async {
      await tester.pumpWidget(
        host(repeatEnabled: false, parentEnabled: true, saving: false),
      );
      expect(find.byKey(const ValueKey('field')), findsNothing);

      await tester.pumpWidget(
        host(repeatEnabled: true, parentEnabled: true, saving: false),
      );
      expect(find.byKey(const ValueKey('field')), findsOneWidget);
      expect(find.text('helper'), findsOneWidget);
    });

    testWidgets('switch disabled when the parent is off or a save is in '
        'flight; field never disabled by saving', (tester) async {
      await tester.pumpWidget(
        host(repeatEnabled: true, parentEnabled: false, saving: false),
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('toggle')))
            .onChanged,
        isNull,
      );

      await tester.pumpWidget(
        host(repeatEnabled: true, parentEnabled: true, saving: true),
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('toggle')))
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('field'))).enabled,
        isTrue,
      );
    });

    testWidgets('shows the error instead of the helper text when set',
        (tester) async {
      controller.error = 'bad range';
      await tester.pumpWidget(
        host(repeatEnabled: true, parentEnabled: true, saving: false),
      );
      expect(find.text('bad range'), findsOneWidget);
      expect(find.text('helper'), findsNothing);
    });
  });
}
