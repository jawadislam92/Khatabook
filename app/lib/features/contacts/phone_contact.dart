import 'dart:convert';

import '../../core/utils/csv.dart';

/// A name and number from the phone's contacts or from a contacts file.
class PhoneContact {
  const PhoneContact(this.name, this.phone);

  final String name;
  final String? phone;

  /// Digits only, for matching numbers written in different ways.
  String get digits => digitsOf(phone);

  @override
  bool operator ==(Object other) =>
      other is PhoneContact && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);
}

String digitsOf(String? phone) => phone?.replaceAll(RegExp(r'\D'), '') ?? '';

/// Last 10 digits, so +92 300 1234567 and 0300 1234567 match.
String phoneKey(String? phone) {
  final d = digitsOf(phone);
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Sorted by name, without empty names and without repeats of the same
/// name and number.
List<PhoneContact> tidyContacts(Iterable<PhoneContact> raw) {
  final seen = <String>{};
  final out = <PhoneContact>[];
  for (final c in raw) {
    final name = c.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) continue;
    final phone = (c.phone ?? '').trim();
    final key = '${name.toLowerCase()}|${phoneKey(phone)}';
    if (!seen.add(key)) continue;
    out.add(PhoneContact(name, phone.isEmpty ? null : phone));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Reads a contacts file exported from a phone or from Google Contacts.
/// Accepts vCard (.vcf) and CSV. Unknown content gives an empty list.
List<PhoneContact> parseContactsFile(String text) {
  final t = text.replaceFirst('﻿', '');
  if (t.toUpperCase().contains('BEGIN:VCARD')) return tidyContacts(_vcard(t));
  return tidyContacts(_csv(t));
}

Iterable<PhoneContact> _vcard(String text) sync* {
  // Join folded lines: a line starting with a space or tab continues the
  // previous one, and quoted printable lines ending in = continue too.
  final lines = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
      lines.last += raw.substring(1);
    } else if (lines.isNotEmpty &&
        lines.last.toUpperCase().contains('QUOTED-PRINTABLE') &&
        lines.last.endsWith('=')) {
      lines.last = lines.last.substring(0, lines.last.length - 1) + raw;
    } else {
      lines.add(raw);
    }
  }
  String? fn;
  String? n;
  final phones = <String>[];
  for (final line in lines) {
    final upper = line.toUpperCase();
    if (upper.startsWith('BEGIN:VCARD')) {
      fn = null;
      n = null;
      phones.clear();
      continue;
    }
    if (upper.startsWith('END:VCARD')) {
      final name = (fn != null && fn.trim().isNotEmpty) ? fn : n;
      if (name != null) {
        yield PhoneContact(name, phones.isEmpty ? null : phones.first);
      }
      continue;
    }
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final head = line.substring(0, colon);
    final key = head.split(';').first.toUpperCase().split('.').last;
    final value = _vcardValue(head, line.substring(colon + 1));
    switch (key) {
      case 'FN':
        fn = value;
      case 'N':
        // N:Family;Given;Middle;Prefix;Suffix
        final parts = value.split(';');
        final given = parts.length > 1 ? parts[1] : '';
        final family = parts.first;
        n = [given, family].where((s) => s.trim().isNotEmpty).join(' ');
      case 'TEL':
        if (value.trim().isNotEmpty) phones.add(value.trim());
    }
  }
}

String _vcardValue(String head, String value) {
  var v = value;
  if (head.toUpperCase().contains('QUOTED-PRINTABLE')) {
    final bytes = <int>[];
    for (var i = 0; i < v.length; i++) {
      if (v[i] == '=' && i + 2 < v.length) {
        final hex = int.tryParse(v.substring(i + 1, i + 3), radix: 16);
        if (hex != null) {
          bytes.add(hex);
          i += 2;
          continue;
        }
      }
      bytes.addAll(utf8.encode(v[i]));
    }
    v = utf8.decode(bytes, allowMalformed: true);
  }
  return v.replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\n', ' ');
}

Iterable<PhoneContact> _csv(String text) sync* {
  final rows = parseCsv(text);
  if (rows.length < 2) return;
  final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(bool Function(String) test) => head.indexWhere(test);
  final nameCol = col(
    (h) => h == 'name' || h == 'display name' || h == 'full name',
  );
  final firstCol = col((h) => h == 'first name' || h == 'given name');
  final lastCol = col((h) => h == 'last name' || h == 'family name');
  var phoneCol = col((h) => h.contains('phone') && h.contains('value'));
  if (phoneCol < 0) {
    phoneCol = col(
      (h) => h.contains('phone') || h.contains('mobile') || h == 'number',
    );
  }
  if (nameCol < 0 && firstCol < 0) return;
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';
  for (final r in rows.skip(1)) {
    var name = cell(r, nameCol);
    if (name.trim().isEmpty) {
      name = [
        cell(r, firstCol),
        cell(r, lastCol),
      ].where((s) => s.trim().isNotEmpty).join(' ');
    }
    // Google puts several numbers in one cell: "0300 1 ::: 0321 2".
    final phone = cell(r, phoneCol).split(':::').first.trim();
    yield PhoneContact(name, phone.isEmpty ? null : phone);
  }
}
