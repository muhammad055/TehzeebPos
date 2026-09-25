import 'package:intl/intl.dart';

final aed = NumberFormat.currency(symbol: 'AED ', decimalDigits: 2);

/// The restaurant runs on UAE time (UTC+4, no DST). Timestamps from the API are
/// UTC; always display them in UAE time regardless of the phone's timezone
/// (an owner may be travelling).
const uaeOffset = Duration(hours: 4);

DateTime parseUtc(String iso) {
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(iso);
  return DateTime.parse(hasZone ? iso : '${iso}Z').toUtc();
}

DateTime toUae(DateTime utc) => utc.toUtc().add(uaeOffset);

/// Current calendar date in UAE, as a date-only DateTime.
DateTime uaeToday() {
  final n = toUae(DateTime.now());
  return DateTime(n.year, n.month, n.day);
}

/// `yyyy-MM-dd` — the format the API's `date`/`from`/`to` query params expect.
String apiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String formatUaeDateTime(DateTime utc) =>
    DateFormat('d MMM, h:mm a').format(toUae(utc));

String formatUaeTime(DateTime utc) => DateFormat('h:mm a').format(toUae(utc));
