// The owner deletes a whole group, but never by a wrong tap.
import 'package:duebook/core/security/pin_store.dart';
import 'package:duebook/features/groups/delete_group_dialog.dart';
import 'package:duebook/features/groups/groups_repository.dart';
import 'package:duebook/features/groups/members_screen.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:duebook/features/spaces/spaces_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'helpers/pump_app.dart';

class _Groups extends PreviewGroupsRepository {
  _Groups(super.ledger);
  final deleted = <String>[];
  @override
  Future<void> deleteGroup(String spaceId) async => deleted.add(spaceId);
}

Future<(ProviderContainer, _Groups)> _open(
  WidgetTester tester,
  String space, {
  bool pin = true,
  String language = 'en',
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/members',
    routes: [
      GoRoute(
        path: '/members',
        builder: (_, _) => MembersScreen(spaceId: space),
      ),
      GoRoute(path: '/spaces', builder: (_, _) => const Text('HOME')),
    ],
  );
  addTearDown(router.dispose);
  final c = await pumpScreen(
    tester,
    Router.withConfig(config: router),
    language: language,
    overrides: [
      groupsRepositoryProvider.overrideWith(
        (ref) => _Groups(ref.watch(ledgerRepositoryProvider)),
      ),
    ],
  );
  if (pin) {
    await tester.runAsync(() => c.read(pinStoreProvider).setPin('2468'));
  }
  await c.read(mySpacesProvider.future);
  await tester.pumpAndSettle();
  return (c, c.read(groupsRepositoryProvider) as _Groups);
}

Future<void> _tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wrong PIN deletes nothing, the right one does', (
    tester,
  ) async {
    final (_, groups) = await _open(tester, 'f');
    await _tap(tester, 'Delete this group');
    expect(find.text('3 other people will lose it too.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1111');
    await tester.pump();
    await _tap(tester, 'Delete');
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    expect(groups.deleted, isEmpty);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.pump();
    await _tap(tester, 'Delete');
    expect(groups.deleted, ['f']);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('cancel deletes nothing', (tester) async {
    final (_, groups) = await _open(tester, 'f');
    await _tap(tester, 'Delete this group');
    await _tap(tester, 'Cancel');
    expect(groups.deleted, isEmpty);
    expect(find.byType(DeleteGroupDialog), findsNothing);
  });

  testWidgets('without a PIN the name is typed', (tester) async {
    final (_, groups) = await _open(tester, 'f', pin: false);
    await _tap(tester, 'Delete this group');
    await tester.enterText(find.byType(TextField), 'Famly');
    await tester.pump();
    await _tap(tester, 'Delete');
    expect(find.text('The name is not the same.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Family');
    await tester.pump();
    await _tap(tester, 'Delete');
    expect(groups.deleted, ['f']);
  });

  testWidgets('the only owner is told why leaving does not work', (
    tester,
  ) async {
    await _open(tester, 'f');
    await _tap(tester, 'Leave this group');
    expect(find.textContaining('You are the only owner'), findsOneWidget);
  });

  testWidgets('alone in the group: delete, no leave', (tester) async {
    await _open(tester, 'p');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Delete this group'), findsOneWidget);
    expect(find.text('Leave this group'), findsNothing);
  });

  testWidgets('a manager cannot delete', (tester) async {
    await _open(tester, 'b');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.text('Leave this group'), findsOneWidget);
    expect(find.text('Delete this group'), findsNothing);
  });

  testWidgets('fits in Urdu', (tester) async {
    await _open(tester, 'f', language: 'ur');
    await _tap(tester, 'یہ گروپ ختم کریں');
    expect(find.byType(DeleteGroupDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
