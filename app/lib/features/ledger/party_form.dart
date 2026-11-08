import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
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
            TextFormField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.personName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l.errorNameRequired : null,
            ),
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
