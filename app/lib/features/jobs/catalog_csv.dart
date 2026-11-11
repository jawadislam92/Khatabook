import 'dart:typed_data';

import '../../core/utils/csv.dart';
import '../../core/utils/money.dart';
import 'jobs_models.dart';

/// Columns of the catalogue file, in the order they are written.
const catalogCsvColumns = [
  'name_en',
  'name_ur',
  'category',
  'unit',
  'sale_price',
  'cost_price',
  'quick_tile',
  'price_editable',
  'active',
];

String _yesNo(bool v) => v ? 'yes' : 'no';

/// The catalogue as a CSV file Excel can open. Cost prices are written only
/// when [includeCost] (the person can see them).
Uint8List catalogCsv(List<CatalogItem> items, {required bool includeCost}) =>
    csvBytes([
      catalogCsvColumns,
      for (final i in items)
        [
          i.nameEn,
          i.nameUr ?? '',
          i.category,
          i.unit,
          Money.format(i.salePricePaisa).replaceAll(',', ''),
          includeCost && i.costPricePaisa != null
              ? Money.format(i.costPricePaisa!).replaceAll(',', '')
              : '',
          _yesNo(i.isFavourite),
          _yesNo(i.allowPriceEdit),
          _yesNo(i.active),
        ],
    ]);

/// A small example the owner can fill in.
Uint8List catalogSampleCsv() => csvBytes([
  catalogCsvColumns,
  [
    'Dome camera 2MP',
    'ڈوم کیمرہ 2MP',
    'camera',
    'pc',
    '4500',
    '3200',
    'yes',
    'no',
    'yes',
  ],
  ['CAT6 cable', '', 'cable', 'm', '60', '', 'no', 'yes', 'yes'],
  [
    'Installation labour',
    '',
    'labour',
    'visit',
    '2000',
    '',
    'yes',
    'yes',
    'yes',
  ],
]);

/// A row that could not be used, with the line number in the file.
class SkippedRow {
  const SkippedRow(this.line, this.reason);
  final int line;
  final CatalogSkip reason;
}

enum CatalogSkip { noName, badPrice, repeated }

class CatalogImportPlan {
  const CatalogImportPlan({
    required this.toAdd,
    required this.toUpdate,
    required this.skipped,
    required this.headerFound,
  });
  final List<CatalogItem> toAdd;
  final List<CatalogItem> toUpdate;
  final List<SkippedRow> skipped;

  /// False when the file has no name column at all (wrong file).
  final bool headerFound;
}

int? _price(String s) {
  final t = s.replaceAll(RegExp(r'[Rr]s\.?|,|\s'), '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0) return -1;
  return (v * 100).round();
}

bool? _flag(String s) {
  final t = s.trim().toLowerCase();
  if (t.isEmpty) return null;
  return const {'yes', 'y', 'true', '1', 'ہاں'}.contains(t);
}

/// Works out what an import would do, without saving anything. Rows are
/// matched to existing items by English name, ignoring case and spaces.
/// Missing columns keep the existing value, or a default for new items.
CatalogImportPlan planCatalogImport(
  String text, {
  required String spaceId,
  required List<CatalogItem> existing,
}) {
  final rows = parseCsv(text);
  if (rows.isEmpty) {
    return const CatalogImportPlan(
      toAdd: [],
      toUpdate: [],
      skipped: [],
      headerFound: false,
    );
  }
  final head = [for (final h in rows.first) h.trim().toLowerCase()];
  int col(List<String> names) => head.indexWhere(names.contains);
  final cName = col(['name_en', 'name', 'item', 'english name']);
  final cUr = col(['name_ur', 'urdu name', 'urdu']);
  final cCat = col(['category']);
  final cUnit = col(['unit']);
  final cSale = col(['sale_price', 'price', 'sale price', 'rate']);
  final cCost = col(['cost_price', 'cost', 'cost price']);
  final cQuick = col(['quick_tile', 'quick tile', 'favourite']);
  final cEdit = col(['price_editable', 'price editable']);
  final cActive = col(['active']);
  if (cName < 0) {
    return const CatalogImportPlan(
      toAdd: [],
      toUpdate: [],
      skipped: [],
      headerFound: false,
    );
  }
  String cell(List<String> r, int i) =>
      i >= 0 && i < r.length ? r[i].trim() : '';
  String key(String n) => n.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  final byName = {for (final i in existing) key(i.nameEn): i};
  final seen = <String>{};
  final add = <CatalogItem>[];
  final update = <CatalogItem>[];
  final skipped = <SkippedRow>[];

  for (var n = 1; n < rows.length; n++) {
    final r = rows[n];
    final line = n + 1;
    final name = cell(r, cName).replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      skipped.add(SkippedRow(line, CatalogSkip.noName));
      continue;
    }
    if (!seen.add(key(name))) {
      skipped.add(SkippedRow(line, CatalogSkip.repeated));
      continue;
    }
    final old = byName[key(name)];
    final sale = _price(cell(r, cSale));
    final cost = _price(cell(r, cCost));
    if (sale == -1 || cost == -1 || (old == null && sale == null)) {
      skipped.add(SkippedRow(line, CatalogSkip.badPrice));
      continue;
    }
    final cat = cell(r, cCat).toLowerCase();
    final unit = cell(r, cUnit).toLowerCase();
    final ur = cell(r, cUr);
    final item = CatalogItem(
      id: old?.id ?? '',
      spaceId: spaceId,
      nameEn: name,
      nameUr: ur.isNotEmpty ? ur : old?.nameUr,
      category: itemCategories.contains(cat) ? cat : (old?.category ?? 'other'),
      unit: itemUnits.contains(unit) ? unit : (old?.unit ?? 'pc'),
      salePricePaisa: sale ?? old!.salePricePaisa,
      costPricePaisa: cost ?? old?.costPricePaisa,
      isFavourite: _flag(cell(r, cQuick)) ?? old?.isFavourite ?? true,
      allowPriceEdit: _flag(cell(r, cEdit)) ?? old?.allowPriceEdit ?? false,
      active: _flag(cell(r, cActive)) ?? old?.active ?? true,
    );
    (old == null ? add : update).add(item);
  }
  return CatalogImportPlan(
    toAdd: add,
    toUpdate: update,
    skipped: skipped,
    headerFound: true,
  );
}
