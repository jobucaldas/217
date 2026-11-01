import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:a217/src/i18n.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('es');
  });

  final oct31 = DateTime(2026, 10, 31, 14, 5);
  final nov19 = DateTime(2026, 11, 19);

  test('Portuguese month names start uppercase', () {
    final dates = const Strings(AppLanguage.pt).dates;
    expect(dates.dayMonth(oct31), '31 de Outubro');
    expect(dates.monthYear(oct31), 'Outubro de 2026');
    expect(dates.shortDayMonth(nov19), '19 de Nov.');
    expect(dates.fullDate(oct31), '31 de Outubro de 2026');
    expect(dates.shortDayMonthTime(oct31), startsWith('31 de Out.'));
  });

  test('Spanish month names start uppercase', () {
    final dates = const Strings(AppLanguage.es).dates;
    expect(dates.dayMonth(oct31), '31 de Octubre');
    expect(dates.monthYear(oct31), 'Octubre de 2026');
    expect(dates.shortDayMonth(nov19), startsWith('19 Nov'));
  });

  test('English is unchanged', () {
    final dates = const Strings(AppLanguage.en).dates;
    expect(dates.dayMonth(oct31), 'October 31');
    expect(dates.monthYear(oct31), 'October 2026');
    expect(dates.shortDayMonth(nov19), 'Nov 19');
  });
}
