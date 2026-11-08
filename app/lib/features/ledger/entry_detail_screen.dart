import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/money_text.dart';
import '../../l10n/app_localizations.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';

class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({
    super.key,
    required this.spaceId,
    required this.partyId,
    required this.entryId,
  });
  final String spaceId;
  final String partyId;
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entries =
        ref.watch(partyEntriesProvider((spaceId, partyId))).value ??
        const <Entry>[];
    final entry = entries.where((e) => e.id == entryId).firstOrNull;
    final pb = ref.watch(partyProvider((spaceId, partyId)));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (entry == null || pb == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final gave = entry.direction == EntryDirection.gave;
    final color = MoneyText.colorFor(context, gave);
    final canChange =
        !entry.isVoided &&
        !entry.isReversal &&
        entry.source == EntrySource.manual;

    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: Tokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(value, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          gave ? l.youGaveTo(pb.party.name) : l.youGotFrom(pb.party.name),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.s4),
        children: [
          Container(
            padding: const EdgeInsets.all(Tokens.s5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: entry.isVoided ? 0.04 : 0.10),
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
            ),
            child: Column(
              children: [
                Icon(
                  gave
                      ? Icons.arrow_outward_rounded
                      : Icons.call_received_rounded,
                  color: color,
                  size: 32,
                ),
                const SizedBox(height: Tokens.s2),
                Text(
                  'Rs ${Money.format(entry.amountPaisa)}',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: 'Roboto',
                    decoration: entry.isVoided
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (entry.isVoided)
                  Chip(
                    label: Text(l.cancelled),
                    backgroundColor: scheme.surfaceContainerHighest,
                  )
                else if (entry.isReversal)
                  Chip(
                    label: Text(l.reversalNote),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.s4),
          row(
            Icons.calendar_today_outlined,
            l.date,
            longDate(context, entry.entryDate),
          ),
          if (entry.note != null)
            row(
              Icons.notes_outlined,
              l.noteOptional.split(' ').first,
              entry.note!,
            ),
          row(
            Icons.person_outline,
            l.addedBy(entry.createdByName ?? ''),
            friendlyDate(context, entry.createdAt),
          ),
          if (entry.wasEdited)
            row(
              Icons.history,
              l.edited,
              friendlyDate(context, entry.updatedAt!),
            ),
          const SizedBox(height: Tokens.s5),
          if (canChange) ...[
            OutlinedButton.icon(
              onPressed: () => _edit(context, ref, entry),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.editEntry),
            ),
            const SizedBox(height: Tokens.s3),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => _void(context, ref, entry),
              icon: const Icon(Icons.block),
              label: Text(l.cancelEntry),
            ),
          ] else
            Text(
              l.cannotChange,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Entry entry) async {
    final l = AppLocalizations.of(context);
    final amount = TextEditingController(text: '${entry.amountPaisa ~/ 100}');
    final note = TextEditingController(text: entry.note ?? '');
    var date = entry.entryDate;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            MediaQuery.viewInsetsOf(ctx).bottom + Tokens.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.editEntry,
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tokens.s4),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.amount,
                  prefixText: 'Rs ',
                ),
              ),
              const SizedBox(height: Tokens.s3),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(friendlyDate(ctx, date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (d != null) setState(() => date = d);
                },
              ),
              const SizedBox(height: Tokens.s3),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: l.noteOptional),
                maxLength: 200,
              ),
              const SizedBox(height: Tokens.s3),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.save),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final paisa = Money.parse(amount.text);
    if (paisa == null || paisa <= 0) return;
    try {
      await ref
          .read(ledgerRepositoryProvider)
          .editEntry(
            entry.id,
            EntryEdit(amountPaisa: paisa, entryDate: date, note: note.text),
          );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.cannotChange)));
      }
    }
  }

  Future<void> _void(BuildContext context, WidgetRef ref, Entry entry) async {
    final l = AppLocalizations.of(context);
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.cancelEntry),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.cancelEntryBody),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: reason,
              decoration: InputDecoration(labelText: l.cancelEntryReason),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.keepEntry),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.yesCancelEntry),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref
          .read(ledgerRepositoryProvider)
          .voidEntry(
            entry.id,
            note: reason.text.trim().isEmpty ? null : reason.text.trim(),
          );
      if (context.mounted) context.pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.cannotChange)));
      }
    }
  }
}
