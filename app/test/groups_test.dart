import 'package:duebook/features/groups/groups_models.dart';
import 'package:duebook/features/groups/groups_repository.dart';
import 'package:duebook/features/groups/join_screen.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

void main() {
  group('InviteLink', () {
    const token =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    test('builds a link on the app subdomain', () {
      expect(
        InviteLink.build(token),
        'https://duebook.sparkingasia.com/join/$token',
      );
    });
    test('parses a full link, a bare code, and text around it', () {
      expect(InviteLink.parse(InviteLink.build(token)), token);
      expect(InviteLink.parse(token), token);
      expect(
        InviteLink.parse(
          'Join us: https://duebook.sparkingasia.com/join/$token thanks',
        ),
        token,
      );
      expect(InviteLink.parse('hello'), isNull);
      expect(InviteLink.parse(''), isNull);
    });
  });

  group('PreviewGroupsRepository', () {
    late PreviewGroupsRepository repo;
    setUp(() => repo = PreviewGroupsRepository(PreviewLedgerRepository()));

    test('activity mixes entries and joins, newest first', () async {
      final items = await repo.activity('f');
      expect(items.any((a) => a.kind == ActivityKind.memberJoined), isTrue);
      expect(items.any((a) => a.kind == ActivityKind.entryAdded), isTrue);
      for (var i = 1; i < items.length; i++) {
        expect(
          items[i - 1].at.isAfter(items[i].at) ||
              items[i - 1].at.isAtSameMomentAs(items[i].at),
          isTrue,
        );
      }
    });

    test('role change and removal update the member list', () async {
      await repo.changeRole('f', 'u3', MemberRole.manager);
      var m = (await repo.members('f')).firstWhere((m) => m.userId == 'u3');
      expect(m.role, MemberRole.manager);
      await repo.removeMember('f', 'u4');
      expect((await repo.members('f')).any((m) => m.userId == 'u4'), isFalse);
    });

    test('month lock round trips', () async {
      expect(await repo.lockedUntil('f'), isNull);
      await repo.setLock('f', DateTime(2026, 10, 31));
      expect(await repo.lockedUntil('f'), DateTime(2026, 10, 31));
      await repo.setLock('f', null);
      expect(await repo.lockedUntil('f'), isNull);
    });
  });

  testWidgets('join screen previews a pasted link and offers Join', (
    tester,
  ) async {
    await pumpScreen(tester, const JoinScreen());
    const token =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    await tester.enterText(
      find.byType(TextField),
      'https://duebook.sparkingasia.com/join/$token',
    );
    await tester.tap(find.text('Check invite'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('invited you to join Khan Family as Member'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
  });

  testWidgets('join screen rejects junk', (tester) async {
    await pumpScreen(tester, const JoinScreen());
    await tester.enterText(find.byType(TextField), 'not a link');
    await tester.tap(find.text('Check invite'));
    await tester.pumpAndSettle();
    expect(
      find.text('That does not look like a Duebook invite.'),
      findsOneWidget,
    );
  });
}
