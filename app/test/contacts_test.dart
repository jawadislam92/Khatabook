// Phone contacts: reading contact files, picking one person, importing many.
import 'package:duebook/features/contacts/contacts_source.dart';
import 'package:duebook/features/contacts/import_contacts_screen.dart';
import 'package:duebook/features/contacts/phone_contact.dart';
import 'package:duebook/features/ledger/ledger_repository.dart';
import 'package:duebook/features/ledger/party_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_app.dart';

class FakeContacts implements ContactsSource {
  FakeContacts({this.access = ContactsAccess.denied, this.grant = true});

  ContactsAccess access;
  final bool grant;
  var asked = 0;
  var settingsOpened = 0;

  static const people = [
    PhoneContact('Zubair Electric', '0300 5550001'),
    PhoneContact('Ayesha Baji', '+92 321 5550002'),
    PhoneContact('Khan Traders', '0333 1234567'),
  ];

  @override
  bool get readsPhone => true;
  @override
  Future<ContactsAccess> check() async => access;
  @override
  Future<ContactsAccess> request() async {
    asked++;
    access = grant ? ContactsAccess.granted : ContactsAccess.blocked;
    return access;
  }

  @override
  Future<List<PhoneContact>> phoneContacts() async => tidyContacts(people);
  @override
  Future<void> openSettings() async => settingsOpened++;
  @override
  Future<List<PhoneContact>?> pickFile() async => null;
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _opener(String spaceId) => Consumer(
  builder: (context, ref, _) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showPartyForm(context, ref, spaceId: spaceId),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  group('contacts file', () {
    test('reads a phone vCard export, including folded and Urdu names', () {
      const vcf =
          'BEGIN:VCARD\r\nVERSION:2.1\r\nN:Raza;Ali;;;\r\nFN:Ali Raza\r\n'
          'TEL;CELL:0300 1112223\r\nTEL;HOME:042 111\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\r\nVERSION:2.1\r\n'
          'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=D8=B9=D9=84=DB=8C\r\n'
          'TEL;CELL:+923215550002\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\nVERSION:3.0\nN:Bhai;Bilal;;;\nTEL;TYPE=CELL:0345\n 9998887\nEND:VCARD\n'
          'BEGIN:VCARD\nVERSION:3.0\nFN:\nEND:VCARD\n';
      final list = parseContactsFile(vcf);
      expect(list, const [
        PhoneContact('Ali Raza', '0300 1112223'),
        PhoneContact('Bilal Bhai', '03459998887'),
        PhoneContact('علی', '+923215550002'),
      ]);
    });

    test('reads a Google Contacts CSV export', () {
      const csv =
          'First Name,Middle Name,Last Name,Phone 1 - Label,Phone 1 - Value\n'
          'Sara,,Khan,Mobile,0300 1 ::: 0321 2\n'
          '"Rafiq, Tailor",,,Mobile,"0333 7"\n'
          ',,,,\n';
      expect(parseContactsFile(csv), const [
        PhoneContact('Rafiq, Tailor', '0333 7'),
        PhoneContact('Sara Khan', '0300 1'),
      ]);
    });

    test('a file with no names gives nothing', () {
      expect(parseContactsFile('hello,world\n1,2\n'), isEmpty);
      expect(parseContactsFile(''), isEmpty);
    });

    test('numbers match with or without the country code', () {
      expect(phoneKey('+92 300 1234567'), phoneKey('0300-1234567'));
    });
  });

  testWidgets('Add person: pick from contacts asks first, then fills the form', (
    tester,
  ) async {
    _phoneSize(tester);
    final fake = FakeContacts();
    await pumpScreen(
      tester,
      _opener('b'),
      overrides: [contactsSourceProvider.overrideWithValue(fake)],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick from contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Use your phone contacts?'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(fake.asked, 1);
    await tester.enterText(find.byType(TextField).last, 'zub');
    await tester.pumpAndSettle();
    expect(find.text('Ayesha Baji'), findsNothing);
    await tester.tap(find.text('Zubair Electric'));
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((f) => f.controller!.text)
        .toList();
    expect(fields, ['Zubair Electric', '0300 5550001']);
  });

  testWidgets('Add person: typing a name suggests matching contacts', (
    tester,
  ) async {
    _phoneSize(tester);
    final fake = FakeContacts(access: ContactsAccess.granted);
    await pumpScreen(
      tester,
      _opener('b'),
      overrides: [contactsSourceProvider.overrideWithValue(fake)],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'ay');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ayesha Baji'));
    await tester.pumpAndSettle();
    final phone = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .last
        .controller!
        .text;
    expect(phone, '+92 321 5550002');
    expect(fake.asked, 0, reason: 'suggestions never ask for access');
  });

  testWidgets('refused for good: points to the phone settings', (tester) async {
    _phoneSize(tester);
    final fake = FakeContacts(access: ContactsAccess.blocked);
    await pumpScreen(
      tester,
      _opener('b'),
      overrides: [contactsSourceProvider.overrideWithValue(fake)],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open phone settings'));
    await tester.pumpAndSettle();
    expect(fake.settingsOpened, 1);
  });

  testWidgets('import adds the picked people and skips those already in', (
    tester,
  ) async {
    _phoneSize(tester);
    final fake = FakeContacts(access: ContactsAccess.granted);
    final container = await pumpScreen(
      tester,
      const ImportContactsScreen(spaceId: 'b'),
      overrides: [contactsSourceProvider.overrideWithValue(fake)],
    );
    await tester.pumpAndSettle();
    final repo = container.read(ledgerRepositoryProvider);
    final before = (await repo.partiesWithBalances('b')).length;

    // Khan Traders is already in the sample business book.
    expect(find.text('Already in this book'), findsOneWidget);
    expect(find.text('Pick people to add'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('Add 2 people'), findsOneWidget);
    await tester.tap(find.text('Ayesha Baji'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1 person'));
    await tester.pumpAndSettle();

    final after = await repo.partiesWithBalances('b');
    expect(after.length, before + 1);
    expect(after.any((p) => p.party.name == 'Zubair Electric'), isTrue);
    expect(after.any((p) => p.party.name == 'Ayesha Baji'), isFalse);
  });

  testWidgets('on the web the import screen asks for a contacts file', (
    tester,
  ) async {
    _phoneSize(tester);
    await pumpScreen(
      tester,
      const ImportContactsScreen(spaceId: 'b'),
      overrides: [contactsSourceProvider.overrideWithValue(FileContactsSource())],
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose contacts file'), findsOneWidget);
    expect(find.text('Pick from contacts'), findsNothing);
  });
}
