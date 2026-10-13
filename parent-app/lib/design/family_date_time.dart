import 'package:intl/intl.dart';

class FamilyDateTime {
  static String format(DateTime? value,
          {String pattern = 'MMM d, y · h:mm a'}) =>
      value == null
          ? 'Not reported'
          : DateFormat(pattern).format(value.toLocal());
  static String parse(Object? value) =>
      format(DateTime.tryParse(value?.toString() ?? ''));
  static bool sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static String dayLabel(DateTime value, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toLocal();
    if (sameDay(value, reference)) return 'Today';
    if (sameDay(
        value, DateTime(reference.year, reference.month, reference.day - 1))) {
      return 'Yesterday';
    }
    return format(value, pattern: 'MMM d, y');
  }
}
