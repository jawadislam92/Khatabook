import 'package:duebook/features/ledger/add_entry_screen.dart';
import 'package:duebook/features/ledger/ledger_models.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets(
    'typing an amount shows it in words and asks a plain question before saving',
    (tester) async {
      final c = await pumpScreen(
        tester,
        const AddEntryScreen(spaceId: 'p', direction: EntryDirection.gave),
      );
      // Step 1: pick a person from the sample list.
      expect(find.text('Who is this with?'), findsOneWidget);
      await tester.tap(find.text('Bilal Bhai'));
      await tester.pumpAndSettle();
      // Step 2: amount.
      expect(find.text('You gave to Bilal Bhai'), findsOneWidget);
      for (final d in ['5', '0', '0', '0']) {
        await tester.tap(find.widgetWithText(InkWell, d).first);
        await tester.pump();
      }
      expect(find.text('Rs 5,000'), findsOneWidget);
      expect(find.text('five thousand'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You gave Rs 5,000 to Bilal Bhai today. Correct?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Yes'));
      await tester.pump(const Duration(milliseconds: 100));
      final repo = c.read(ledgerRepositoryProvider);
      final bilal = (await repo.partiesWithBalances('p'))
          .firstWhere((p) => p.party.name == 'Bilal Bhai');
      expect(bilal.balancePaisa, 800000);
    },
  );

  testWidgets('quick amount chips fill the keypad', (tester) async {
    await pumpScreen(
      tester,
      const AddEntryScreen(spaceId: 'p', direction: EntryDirection.got),
    );
    await tester.tap(find.text('Corner Shop'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ActionChip, '2,000'));
    await tester.tap(find.widgetWithText(ActionChip, '2,000'));
    await tester.pump();
    expect(find.text('Rs 2,000'), findsOneWidget);
  });
}
