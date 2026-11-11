// Catalogue import and export: Excel-style files, Urdu names, rows that
// cannot be used are left out with a reason, nothing saved before OK.
import 'dart:convert';

import 'package:duebook/core/update/update_check.dart';
import 'package:duebook/features/jobs/catalog_csv.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

const _cam = CatalogItem(
  id: 'i1',
  spaceId: 'b',
  nameEn: 'Dome camera 2MP',
  nameUr: 'ڈوم کیمرہ',
  unit: 'pc',
  category: 'camera',
  salePricePaisa: 450000,
  costPricePaisa: 320000,
  isFavourite: true,
);

String _text(List<int> bytes) => utf8.decode(bytes);

class _Updates implements UpdateSource {
  _Updates(this.mine, this.online);
  final int mine;
  final int online;
  @override
  Future<int> currentBuild() async => mine;
  @override
  Future<AppUpdate?> latest() async => AppUpdate(
    build: online,
    apkUrl: 'https://duebook.sparkingasia.com/duebook.apk',
    notes: 'Faster bills',
  );
}

void main() {
  test('export then import of the same file changes nothing new', () {
    final bytes = catalogCsv([_cam], includeCost: true);
    expect(bytes.take(3), [
      0xEF,
      0xBB,
      0xBF,
    ], reason: 'Excel needs this for Urdu');
    final text = _text(bytes);
    expect(text, contains('Dome camera 2MP'));
    expect(text, contains('ڈوم کیمرہ'));
    expect(text, contains('3200'));
    final plan = planCatalogImport(text, spaceId: 'b', existing: [_cam]);
    expect(plan.toAdd, isEmpty);
    expect(plan.toUpdate.single.id, 'i1');
    expect(plan.toUpdate.single.salePricePaisa, 450000);
    expect(plan.skipped, isEmpty);
  });

  test('cost prices stay out of the file for people who cannot see them', () {
    final text = _text(catalogCsv([_cam], includeCost: false));
    expect(text, isNot(contains('3200')));
  });

  test('a file typed in Excel: quotes, Rs, commas, yes and no, Urdu', () {
    const csv =
        'Name,Urdu name,Category,Unit,Price,Cost,Quick tile\r\n'
        '"Bullet camera, 5MP",بلٹ کیمرہ,camera,pc,"Rs 6,500",,yes\r\n'
        'CAT6 cable,,cable,m,60,45,no\r\n'
        'dome CAMERA 2mp,,,,4800,,\r\n'
        ',,,,100,,\r\n'
        'Screws,,accessory,box,cheap,,\r\n'
        'CAT6 cable,,cable,m,70,,\r\n'
        'Inverter 5kW,,inverter,set,,,\r\n';
    final plan = planCatalogImport(csv, spaceId: 'b', existing: [_cam]);
    expect(plan.toAdd.map((i) => i.nameEn), [
      'Bullet camera, 5MP',
      'CAT6 cable',
    ]);
    final bullet = plan.toAdd.first;
    expect(bullet.salePricePaisa, 650000);
    expect(bullet.nameUr, 'بلٹ کیمرہ');
    expect(bullet.isFavourite, isTrue);
    expect(plan.toAdd.last.costPricePaisa, 4500);
    expect(plan.toAdd.last.unit, 'm');
    // Matched by name ignoring case; columns left empty keep what was there.
    final cam = plan.toUpdate.single;
    expect(cam.id, 'i1');
    expect(cam.salePricePaisa, 480000);
    expect(cam.costPricePaisa, 320000);
    expect(cam.nameUr, 'ڈوم کیمرہ');
    expect(cam.category, 'camera');
    expect(plan.skipped.map((s) => (s.line, s.reason)), [
      (5, CatalogSkip.noName),
      (6, CatalogSkip.badPrice),
      (7, CatalogSkip.repeated),
      (8, CatalogSkip.badPrice),
    ]);
  });

  test('unknown units and categories fall back instead of failing', () {
    final plan = planCatalogImport(
      'name_en,sale_price,unit,category\nRelay,250,piece,gadget\n',
      spaceId: 'b',
      existing: const [],
    );
    expect(plan.toAdd.single.unit, 'pc');
    expect(plan.toAdd.single.category, 'other');
  });

  test('a file without a name column is the wrong file', () {
    final plan = planCatalogImport(
      'date,amount\n2026-01-01,5\n',
      spaceId: 'b',
      existing: const [],
    );
    expect(plan.headerFound, isFalse);
  });

  test('the sample file imports cleanly', () {
    final plan = planCatalogImport(
      _text(catalogSampleCsv()),
      spaceId: 'b',
      existing: const [],
    );
    expect(plan.toAdd, hasLength(3));
    expect(plan.skipped, isEmpty);
  });

  group('update card', () {
    testWidgets('shows when the website has a newer build', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: UpdateBanner()),
        overrides: [updateSourceProvider.overrideWithValue(_Updates(2, 3))],
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version is ready'), findsOneWidget);
      expect(find.text('Faster bills'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('stays hidden when already up to date', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: UpdateBanner()),
        overrides: [updateSourceProvider.overrideWithValue(_Updates(3, 3))],
      );
      await tester.pumpAndSettle();
      expect(find.text('A new version is ready'), findsNothing);
    });
  });
}
