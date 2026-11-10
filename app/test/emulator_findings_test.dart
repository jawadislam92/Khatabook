// Checks for the six problems found by hand on the emulator on 10 November.
import 'package:duebook/core/utils/dates.dart';
import 'package:duebook/features/invoices/finish_job_screen.dart';
import 'package:duebook/features/invoices/invoice_labels.dart';
import 'package:duebook/features/invoices/invoice_models.dart';
import 'package:duebook/features/jobs/catalog_screen.dart';
import 'package:duebook/features/jobs/jobs_models.dart';
import 'package:duebook/features/jobs/jobs_repository.dart';
import 'package:duebook/features/ledger/party_form.dart';
import 'package:duebook/features/ledger/space_home_screen.dart';
import 'package:duebook/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/pump_app.dart';

Invoice _invoice({required int received, required InvoiceStatus status}) =>
    Invoice(
      id: 'i',
      spaceId: 'b',
      customerId: 'c',
      customerName: 'Ali',
      number: 'INV-1',
      issuedAt: DateTime(2026, 11, 10),
      subtotalPaisa: 250000,
      discountPaisa: 0,
      taxRateBp: 0,
      taxPaisa: 0,
      totalPaisa: 250000,
      receivedPaisa: received,
      balancePaisa: 250000 - received,
      status: status,
    );

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('Urdu times name the part of the day, not "a" or "p"', () async {
    await initializeDateFormatting('ur');
    await initializeDateFormatting('en');
    final ur = lookupAppLocalizations(const Locale('ur'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(clockTimeFor(ur, DateTime(2026, 11, 11, 10)), '10:00 صبح');
    expect(clockTimeFor(ur, DateTime(2026, 11, 11, 15)), '3:00 دوپہر');
    expect(clockTimeFor(ur, DateTime(2026, 11, 11, 17, 30)), '5:30 شام');
    expect(clockTimeFor(ur, DateTime(2026, 11, 11, 22)), '10:00 رات');
    expect(clockTimeFor(ur, DateTime(2026, 11, 11, 2)), '2:00 رات');
    expect(clockTimeFor(en, DateTime(2026, 11, 11, 10)), contains('AM'));
  });

  test('a bill with some money in says Part paid', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(
      invoiceStatusLabel(
        l,
        _invoice(received: 0, status: InvoiceStatus.issued),
      ),
      'Unpaid',
    );
    expect(
      invoiceStatusLabel(
        l,
        _invoice(received: 100000, status: InvoiceStatus.issued),
      ),
      'Part paid',
    );
    expect(
      invoiceStatusLabel(
        l,
        _invoice(received: 250000, status: InvoiceStatus.paid),
      ),
      'Paid',
    );
  });

  testWidgets('adding a person with a name already in the book asks first', (
    tester,
  ) async {
    _phoneSize(tester);
    await pumpScreen(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showPartyForm(context, ref, spaceId: 'b'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'khan traders ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Already in this book?'), findsOneWidget);
    expect(find.textContaining('Khan Traders'), findsWidgets);

    // Cancel keeps the form open so the name can be changed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Already in this book?'), findsNothing);
    expect(find.text('New person'), findsOneWidget);

    // A new name saves without a question.
    await tester.enterText(find.byType(TextFormField).first, 'Brand New Name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Already in this book?'), findsNothing);
    expect(find.text('New person'), findsNothing);
  });

  testWidgets('picking an item from search closes the keyboard', (
    tester,
  ) async {
    _phoneSize(tester);
    final holder = ValueNotifier<Widget>(const SizedBox.shrink());
    addTearDown(holder.dispose);
    final container = await pumpScreen(
      tester,
      ValueListenableBuilder<Widget>(
        valueListenable: holder,
        builder: (_, w, _) => w,
      ),
    );
    final jobs =
        container.read(jobsRepositoryProvider) as PreviewJobsRepository;
    await jobs.ready;
    final job = (await jobs.jobs('b')).firstWhere((j) => j.status.isOpen);
    final item = (await jobs.catalog('b')).first;
    holder.value = FinishJobScreen(spaceId: 'b', jobId: job.id);
    await tester.pumpAndSettle();

    final search = find.byType(TextField).first;
    await tester.tap(search);
    await tester.enterText(search, item.nameEn.substring(0, 3));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text(item.nameEn).last);
    await tester.pumpAndSettle();
    expect(
      tester.testTextInput.isVisible,
      isFalse,
      reason: 'the keyboard must not cover the bill button',
    );
  });

  testWidgets('a new catalog item is a quick tile unless switched off', (
    tester,
  ) async {
    _phoneSize(tester);
    await pumpScreen(tester, const CatalogScreen(spaceId: 'b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New item'));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, 'Show as quick tile');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('the who recorded what card writes amounts as money', (
    tester,
  ) async {
    _phoneSize(tester);
    await pumpScreen(tester, const SpaceHomeScreen(spaceId: 'b'));
    await tester.pumpAndSettle();
    final cardTexts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((t) => RegExp(r'^ (Rs )?[\d,]+ *$').hasMatch(t))
        .toList();
    expect(cardTexts, isNotEmpty);
    expect(
      cardTexts.every((t) => t.contains('Rs ')),
      isTrue,
      reason: '$cardTexts',
    );
  });
}
