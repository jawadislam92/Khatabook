import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'phone_contact.dart';

enum ContactsAccess { granted, denied, blocked }

/// Where contacts come from: the phone itself on Android and iPhone, or a
/// contacts file the person chooses (the web, and as a second way on phones).
abstract class ContactsSource {
  bool get readsPhone;
  Future<ContactsAccess> check();
  Future<ContactsAccess> request();
  Future<List<PhoneContact>> phoneContacts();
  Future<void> openSettings();

  /// Null when the person closes the file chooser.
  Future<List<PhoneContact>?> pickFile();
}

class DeviceContactsSource extends FileContactsSource {
  @override
  bool get readsPhone => true;

  static ContactsAccess _map(fc.PermissionStatus s) => switch (s) {
    fc.PermissionStatus.granted ||
    fc.PermissionStatus.limited => ContactsAccess.granted,
    fc.PermissionStatus.permanentlyDenied ||
    fc.PermissionStatus.restricted => ContactsAccess.blocked,
    _ => ContactsAccess.denied,
  };

  @override
  Future<ContactsAccess> check() async {
    try {
      return _map(
        await fc.FlutterContacts.permissions.check(fc.PermissionType.read),
      );
    } catch (_) {
      return ContactsAccess.denied;
    }
  }

  @override
  Future<ContactsAccess> request() async {
    try {
      return _map(
        await fc.FlutterContacts.permissions.request(fc.PermissionType.read),
      );
    } catch (_) {
      return ContactsAccess.blocked;
    }
  }

  @override
  Future<List<PhoneContact>> phoneContacts() async {
    final all = await fc.FlutterContacts.getAll(
      properties: {fc.ContactProperty.phone},
    );
    return tidyContacts(
      all.map(
        (c) => PhoneContact(
          c.displayName ?? '',
          c.phones.isEmpty ? null : c.phones.first.number,
        ),
      ),
    );
  }

  @override
  Future<void> openSettings() async {
    try {
      await fc.FlutterContacts.permissions.openSettings();
    } catch (_) {}
  }
}

/// No phone contacts here; only a contacts file.
class FileContactsSource implements ContactsSource {
  @override
  bool get readsPhone => false;
  @override
  Future<ContactsAccess> check() async => ContactsAccess.denied;
  @override
  Future<ContactsAccess> request() async => ContactsAccess.blocked;
  @override
  Future<List<PhoneContact>> phoneContacts() async => const [];
  @override
  Future<void> openSettings() async {}

  @override
  Future<List<PhoneContact>?> pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vcf', 'csv'],
      withData: true,
    );
    final bytes = res?.files.firstOrNull?.bytes;
    if (bytes == null) return null;
    return parseContactsFile(utf8.decode(bytes, allowMalformed: true));
  }
}

final contactsSourceProvider = Provider<ContactsSource>((ref) {
  final phone =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  return phone ? DeviceContactsSource() : FileContactsSource();
});

/// Contacts already at hand without asking anything: the phone's contacts
/// when access was given before, or the file chosen earlier in this run.
/// Used for suggestions while typing a name.
final knownContactsProvider = FutureProvider<List<PhoneContact>>((ref) async {
  final fromFile = ref.watch(chosenContactsFileProvider);
  if (fromFile != null) return fromFile;
  final source = ref.watch(contactsSourceProvider);
  if (!source.readsPhone) return const [];
  if (await source.check() != ContactsAccess.granted) return const [];
  return source.phoneContacts();
});

/// The contacts file chosen in this run, kept so it is not asked for again.
final chosenContactsFileProvider =
    NotifierProvider<ChosenContactsFile, List<PhoneContact>?>(
      ChosenContactsFile.new,
    );

class ChosenContactsFile extends Notifier<List<PhoneContact>?> {
  @override
  List<PhoneContact>? build() => null;
  void set(List<PhoneContact> list) => state = list;
}

/// Gets contacts for picking or importing. On a phone it asks for access
/// the first time (with a short reason first), and points to the phone
/// settings when access was refused for good. Elsewhere it asks for a file.
/// Null means the person backed out.
Future<List<PhoneContact>?> loadContacts(
  BuildContext context,
  WidgetRef ref, {
  bool chooseFile = false,
}) async {
  final l = AppLocalizations.of(context);
  final source = ref.read(contactsSourceProvider);
  if (!source.readsPhone || chooseFile) {
    final kept = ref.read(chosenContactsFileProvider);
    if (kept != null && !chooseFile) return kept;
    final picked = await source.pickFile();
    if (picked != null) {
      ref.read(chosenContactsFileProvider.notifier).set(picked);
      ref.invalidate(knownContactsProvider);
    }
    return picked;
  }
  var access = await source.check();
  if (access == ContactsAccess.denied) {
    if (!context.mounted) return null;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.contacts_rounded),
        title: Text(l.contactsAllowTitle),
        content: Text(l.contactsAllowBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.contactsNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.contactsAllow),
          ),
        ],
      ),
    );
    if (go != true) return null;
    access = await source.request();
  }
  if (access != ContactsAccess.granted) {
    if (!context.mounted) return null;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.contactsDenied),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.contactsOpenSettings),
          ),
        ],
      ),
    );
    if (open == true) await source.openSettings();
    return null;
  }
  ref.invalidate(knownContactsProvider);
  return source.phoneContacts();
}
