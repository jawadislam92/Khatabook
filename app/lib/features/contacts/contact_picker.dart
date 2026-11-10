import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'contacts_source.dart';
import 'phone_contact.dart';

/// Lets the person pick one contact. Null when nothing was picked.
Future<PhoneContact?> pickContact(BuildContext context, WidgetRef ref) async {
  final list = await loadContacts(context, ref);
  if (list == null || !context.mounted) return null;
  return showModalBottomSheet<PhoneContact>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PickerSheet(contacts: list),
  );
}

/// Contacts whose name or number matches what was typed.
List<PhoneContact> matchContacts(List<PhoneContact> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  final qd = digitsOf(q);
  return all
      .where(
        (c) =>
            c.name.toLowerCase().contains(q) ||
            (qd.length >= 3 && c.digits.contains(qd)),
      )
      .toList();
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.contacts});
  final List<PhoneContact> contacts;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = matchContacts(widget.contacts, _query);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.s4),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.contactsSearch,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: Tokens.s2),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(l.contactsNone))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(c.name.characters.first.toUpperCase()),
                          ),
                          title: Text(c.name),
                          subtitle: c.phone == null ? null : Text(c.phone!),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
