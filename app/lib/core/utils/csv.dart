import 'dart:convert';
import 'dart:typed_data';

/// Reads CSV text as rows of cells. Handles quoted cells with commas, line
/// breaks and doubled quotes, Windows line ends, and a leading byte order
/// mark (Excel adds one). Rows with only empty cells are dropped.
List<List<String>> parseCsv(String text) {
  final t = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((s) => s.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((s) => s.isNotEmpty)) rows.add(row);
  return rows;
}

/// One cell, quoted when it holds a comma, a quote or a line break.
String csvCell(String v) =>
    RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

/// UTF-8 bytes with a byte order mark, so Excel shows Urdu correctly.
Uint8List csvBytes(List<List<String>> rows) {
  final text = rows.map((r) => r.map(csvCell).join(',')).join('\r\n');
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('$text\r\n')]);
}
