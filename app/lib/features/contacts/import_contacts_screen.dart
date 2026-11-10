import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/load_error.dart';
import '../../l10n/app_localizations.dart';
import '../ledger/ledger_repository.dart';
import 'contact_picker.dart';
import 'contacts_source.dart';
import 'phone_contact.dart';

/// Add many people to a book at once from the phone's contacts or a
/// contacts file. People already in the book are shown but cannot be
/// picked again.
class ImportContactsScreen extends ConsumerStatefulWidget {
  const ImportContactsScreen({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<ImportContactsScreen> createState() =>
      _ImportContactsScreenState();
}

class _ImportContactsScreenState extends ConsumerState<ImportContactsScreen> {
  List<PhoneContact>? _contacts;
  final _picked = <PhoneContact>{};
  var _query = '';
  var _saving = false;

  @override
  void initState() {
    super.initState();
    // On a phone, go straight to the phone's contacts.
    if (ref.read(contactsSourceProvider).readsPhone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load({bool chooseFile = false}) async {
    final list = await loadContacts(context, ref, chooseFile: chooseFile);
    if (list != null && mounted) {
      setState(() {
        _contacts = list;
        _picked.clear();
      });
    }
  }

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    final repo = ref.read(ledgerRepositoryProvider);
    var added = 0;
    var failed = false;
    for (final c in _picked.toList()) {
      try {
        await repo.addParty(widget.spaceId, name: c.name, phone: c.phone);
        added++;
      } catch (_) {
        failed = true;
        break;
      }
    }
    ref.invalidate(partyBalancesProvider(widget.spaceId));
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (failed) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
      if (added == 0) return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.contactsAdded(added))));
    Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final readsPhone = ref.watch(contactsSourceProvider).readsPhone;
    final existing = ref.watch(partyBalancesProvider(widget.spaceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(l.contactsImport),
        actions: [
          if (_contacts != null)
            IconButton(
              tooltip: l.contactsChooseFile,
              icon: const Icon(Icons.upload_file_rounded),
              onPressed: () => _load(chooseFile: true),
            ),
        ],
      ),
      bottomNavigationBar: _contacts == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s4),
                child: FilledButton.icon(
                  onPressed: _picked.isEmpty || _saving ? null : _add,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(l.contactsAddCount(_picked.length)),
                ),
              ),
            ),
      body: existing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => LoadError(
          onRetry: () => ref.invalidate(partyBalancesProvider(widget.spaceId)),
        ),
        data: (people) {
          final contacts = _contacts;
          if (contacts == null) return _start(l, readsPhone);
          final names = {
            for (final p in people) p.party.name.trim().toLowerCase(),
          };
          final phones = {
            for (final p in people)
              if (phoneKey(p.party.phone).length >= 7) phoneKey(p.party.phone),
          };
          bool inBook(PhoneContact c) =>
              names.contains(c.name.toLowerCase()) ||
              (phoneKey(c.phone).length >= 7 &&
                  phones.contains(phoneKey(c.phone)));
          final shown = matchContacts(contacts, _query);
          final free = shown.where((c) => !inBook(c)).toList();
          final allPicked = free.isNotEmpty && free.every(_picked.contains);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s4,
                  Tokens.s2,
                  Tokens.s4,
                  0,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: l.contactsSearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (free.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (allPicked) {
                        _picked.removeAll(free);
                      } else {
                        _picked.addAll(free);
                      }
                    }),
                    child: Text(
                      allPicked ? l.contactsClear : l.contactsSelectAll,
                    ),
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(l.contactsNone))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final c = shown[i];
                          final already = inBook(c);
                          return CheckboxListTile(
                            value: already || _picked.contains(c),
                            onChanged: already || _saving
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      _picked.add(c);
                                    } else {
                                      _picked.remove(c);
                                    }
                                  }),
                            title: Text(c.name),
                            subtitle: Text(
                              already ? l.contactsAlreadyIn : (c.phone ?? ''),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _start(AppLocalizations l, bool readsPhone) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Tokens.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.contacts_rounded, size: 56),
          const SizedBox(height: Tokens.s4),
          if (readsPhone) ...[
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.contacts_rounded),
              label: Text(l.contactsPick),
            ),
            const SizedBox(height: Tokens.s4),
          ],
          Text(l.contactsFileHint, textAlign: TextAlign.center),
          const SizedBox(height: Tokens.s3),
          OutlinedButton.icon(
            onPressed: () => _load(chooseFile: true),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(l.contactsChooseFile),
          ),
        ],
      ),
    ),
  );
}
