import 'package:intl/intl.dart';

/// Date formats shown in the UI. `intl` writes Portuguese and Spanish month
/// names in lowercase ("31 de outubro", "19 de nov."); the app shows them
/// with a capital first letter. English output is unchanged.
class AppDates {
  const AppDates(this.locale);

  /// `intl` locale, see `AppLanguage.dateLocale`.
  final String locale;

  /// "October 2026", "Outubro de 2026".
  String monthYear(DateTime date) => _format(DateFormat.yMMMM(locale), date);

  /// "October 31", "31 de Outubro".
  String dayMonth(DateTime date) =>
      _format(_ordinal(date, 'MMMM d', DateFormat.MMMMd(locale)), date);

  /// "Nov 19", "19 de Nov.".
  String shortDayMonth(DateTime date) =>
      _format(_ordinal(date, 'MMM d', DateFormat.MMMd(locale)), date);

  /// "11/02" in English, "02/11" elsewhere.
  String numericDayMonth(DateTime date) => DateFormat(
        locale.startsWith('en') ? 'MM/dd' : 'dd/MM',
        locale,
      ).format(date);

  /// "09:20".
  String time(DateTime date) => DateFormat.Hm(locale).format(date);

  /// "October 31, 2026", "31 de Outubro de 2026".
  String fullDate(DateTime date) => _format(
      _ordinal(date, 'MMMM d', DateFormat.yMMMMd(locale), suffix: ', y'), date);

  /// "Nov 19 14:05", "19 de Nov. 14:05".
  String shortDayMonthTime(DateTime date) =>
      _format(_ordinal(date, 'MMM d', DateFormat.MMMd(locale), suffix: ' HH:mm'),
          date);

  /// English writes "3rd" instead of "3": [pattern] plus the day's suffix
  /// and [suffix]. Other languages use [plain].
  DateFormat _ordinal(DateTime date, String pattern, DateFormat plain,
      {String suffix = ''}) {
    if (!locale.startsWith('en')) {
      return suffix == ' HH:mm' ? plain.add_Hm() : plain;
    }
    final d = date.day;
    final tens = d % 100;
    final word = (tens >= 11 && tens <= 13)
        ? 'th'
        : switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return DateFormat("$pattern'$word'$suffix", locale);
  }

  String _format(DateFormat format, DateTime date) =>
      capitalizeMonth(format.format(date), date, locale);
}

/// Capitalizes the month name of [date] inside [formatted], whichever of the
/// long or short forms it uses.
String capitalizeMonth(String formatted, DateTime date, String locale) {
  for (final pattern in const ['MMMM', 'LLLL', 'MMM', 'LLL']) {
    final name = DateFormat(pattern, locale).format(date);
    if (name.isEmpty) continue;
    final at = formatted.indexOf(name);
    if (at < 0) continue;
    return formatted.replaceRange(at, at + 1, name[0].toUpperCase());
  }
  return formatted;
}
