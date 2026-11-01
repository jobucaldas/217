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
  String dayMonth(DateTime date) => _format(DateFormat.MMMMd(locale), date);

  /// "Nov 19", "19 de Nov.".
  String shortDayMonth(DateTime date) => _format(DateFormat.MMMd(locale), date);

  /// "October 31, 2026", "31 de Outubro de 2026".
  String fullDate(DateTime date) => _format(DateFormat.yMMMMd(locale), date);

  /// "Nov 19 14:05", "19 de Nov. 14:05".
  String shortDayMonthTime(DateTime date) =>
      _format(DateFormat.MMMd(locale).add_Hm(), date);

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
