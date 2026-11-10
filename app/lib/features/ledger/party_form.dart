import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../contacts/contact_picker.dart';
import '../contacts/contacts_source.dart';
import '../../l10n/app_localizations.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';

/// Add or edit a person. Returns the saved party, or null if dismissed.
Future<Party?> showPartyForm(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  Party? existing,
  String? initialName,
}) {
  final l = AppLocalizations.of(context);
  final name = TextEditingController(text: existing?.name ?? initialName ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  final key = GlobalKey<FormState>();
  return showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        Tokens.s4,
        0,
        Tokens.s4,
        MediaQuery.viewInsetsOf(ctx).bottom + Tokens.s4,
      ),
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null ? l.newPerson : l.editPerson,
              style: Theme.of(ctx).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Tokens.s4),
            if (existing == null) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final c = await pickContact(ctx, ref);
                  if (c == null) return;
                  name.text = c.name;
                  phone.text = c.phone ?? '';
                },
                icon: const Icon(Icons.contacts_rounded),
                label: Text(l.contactsPick),
              ),
              const SizedBox(height: Tokens.s3),
            ],
            TextFormField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.personName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.errorNameRequired : null,
            ),
            if (existing == null) _Suggestions(name: name, phone: phone),
            const SizedBox(height: Tokens.s3),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.phoneOptional,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: Tokens.s4),
            FilledButton(
              onPressed: () async {
                if (!key.currentState!.validate()) return;
                final repo = ref.read(ledgerRepositoryProvider);
                final p = phone.text.trim().isEmpty ? null : phone.text.trim();
                if (existing == null) {
                  final same = await _samePerson(repo, spaceId, name.text, p);
                  if (!ctx.mounted) return;
                  if (same != null && !await _confirmDuplicate(ctx, l, same)) {
                    return;
                  }
                }
                final saved = existing == null
                    ? await repo.addParty(spaceId, name: name.text, phone: p)
                    : await repo.updateParty(
                        existing.copyWith(name: name.text.trim(), phone: p),
                      );
                if (ctx.mounted) Navigator.pop(ctx, saved);
              },
              child: Text(l.save),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Someone already in this book with the same name or phone number, or
/// null. A failed lookup returns null, so saving still works offline.
Future<Party?> _samePerson(
  LedgerRepository repo,
  String spaceId,
  String name,
  String? phone,
) async {
  try {
    final digits = phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    final wanted = name.trim().toLowerCase();
    for (final pb in await repo.partiesWithBalances(spaceId)) {
      final other = pb.party;
      final otherDigits = other.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (other.name.trim().toLowerCase() == wanted ||
          (digits.length >= 7 && digits == otherDigits)) {
        return other;
      }
    }
  } catch (_) {}
  return null;
}

Future<bool> _confirmDuplicate(
  BuildContext context,
  AppLocalizations l,
  Party same,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.duplicatePersonTitle),
        content: Text(
          l.duplicatePersonBody(
            same.phone == null ? same.name : '${same.name} (${same.phone})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.addAnyway),
          ),
        ],
      ),
    ) ??
    false;

/// While a new name is typed, shows up to three matching contacts from the
/// phone (or the chosen contacts file). A tap fills name and number.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.name, required this.phone});
  final TextEditingController name;
  final TextEditingController phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(knownContactsProvider).value ?? const [];
    if (all.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: name,
      builder: (context, v, _) {
        final q = v.text.trim();
        if (q.length < 2) return const SizedBox.shrink();
        final hits = matchContacts(all, q)
            .where((c) => c.name != q || (c.phone ?? '') != phone.text)
            .take(3)
            .toList();
        if (hits.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Tokens.s2),
          child: Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s1,
            children: [
              for (final c in hits)
                ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(
                    c.phone == null ? c.name : '${c.name}  ${c.phone}',
                  ),
                  onPressed: () {
                    name.text = c.name;
                    phone.text = c.phone ?? '';
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
