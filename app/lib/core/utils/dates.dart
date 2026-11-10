import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

/// Short, friendly dates: Today, Yesterday, then "8 Nov 2026".
String friendlyDate(BuildContext context, DateTime d) {
  final l = AppLocalizations.of(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return l.today;
  if (diff == 1) return l.yesterday;
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.yMMMd(locale).format(d);
}

String longDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMMEEEEd(Localizations.localeOf(context).toString()).format(d);

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The time of day, like "3:00 PM", or "3:00 دوپہر" in Urdu.
///
/// The date library writes AM and PM in Urdu as a bare "a" and "p", so the
/// Urdu time names the part of the day instead.
String clockTime(BuildContext context, DateTime d) =>
    clockTimeFor(AppLocalizations.of(context), d);

String clockTimeFor(AppLocalizations l, DateTime d) {
  if (l.localeName != 'ur') return DateFormat.jm(l.localeName).format(d);
  final part = switch (d.hour) {
    >= 4 && < 12 => l.timeMorning,
    >= 12 && < 16 => l.timeAfternoon,
    >= 16 && < 19 => l.timeEvening,
    _ => l.timeNight,
  };
  return '${DateFormat('h:mm', 'ur').format(d)} $part';
}
