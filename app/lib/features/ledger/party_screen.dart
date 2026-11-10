import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/money_text.dart';
import '../../l10n/app_localizations.dart';
import '../spaces/spaces_repository.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'party_form.dart';
import 'share_actions.dart';

class PartyScreen extends ConsumerWidget {
  const PartyScreen({super.key, required this.spaceId, required this.partyId});
  final String spaceId;
  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pb = ref.watch(partyProvider((spaceId, partyId)));
    final entries = ref.watch(partyEntriesProvider((spaceId, partyId)));
    final simple = ref.watch(appSettingsProvider).simpleMode;
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    final spaceName = space == null ? '' : space.name;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (pb == null) {
      // The person comes from the balances list; no person once that list
      // has loaded means it failed or the person is gone.
      final balances = ref.watch(partyBalancesProvider(spaceId));
      if (balances.isLoading && !balances.hasError) {
        return const LoadingScaffold();
      }
      return LoadErrorScaffold(
        onRetry: () => ref.invalidate(partyBalancesProvider(spaceId)),
      );
    }
    final sign = pb.settled ? null : pb.willGet;
    final color = pb.settled
        ? scheme.onSurfaceVariant
        : MoneyText.colorFor(context, sign);

    return Scaffold(
      appBar: AppBar(
        title: Text(pb.party.name),
        actions: [
          IconButton(
            tooltip: l.editPerson,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showPartyForm(
              context,
              ref,
              spaceId: spaceId,
              existing: pb.party,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') shareStatement(context, ref, pb, spaceName);
              if (v == 'sms') sendReminderMessage(context, pb, sms: true);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(l.statementPdf),
                ),
              ),
              PopupMenuItem(
                value: 'sms',
                child: ListTile(
                  leading: const Icon(Icons.sms_outlined),
                  title: Text(l.sendSms),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s2,
              Tokens.s4,
              Tokens.s3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(Tokens.s4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(Tokens.radiusLarge),
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        pb.settled
                            ? l.settled
                            : (pb.willGet ? l.youWillGet : l.youWillGive),
                        style: text.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      MoneyText(
                        paisa: pb.balancePaisa,
                        sign: sign,
                        size: simple ? 38 : 32,
                        words: simple,
                        align: TextAlign.center,
                      ),
                      if (pb.party.phone != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          pb.party.phone!,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Tokens.s3),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MoneyText.colorFor(context, true),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => context.push(
                          '/space/$spaceId/add?direction=gave&party=$partyId',
                        ),
                        icon: const Icon(Icons.arrow_outward_rounded),
                        label: Text(l.gave),
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MoneyText.colorFor(context, false),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => context.push(
                          '/space/$spaceId/add?direction=got&party=$partyId',
                        ),
                        icon: const Icon(Icons.call_received_rounded),
                        label: Text(l.got),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Tokens.s2),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pb.settled
                            ? null
                            : () => sendReminderMessage(context, pb),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(
                          l.sendWhatsApp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: Tokens.s2),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _setReminder(context, ref),
                        icon: const Icon(Icons.alarm_add_outlined),
                        label: Text(l.remind),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => LoadError(
                onRetry: () =>
                    ref.invalidate(partyEntriesProvider((spaceId, partyId))),
              ),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Tokens.s5),
                      child: Text(
                        l.noEntriesYet,
                        textAlign: TextAlign.center,
                        style: text.bodyLarge,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        Tokens.s4,
                        0,
                        Tokens.s4,
                        Tokens.s6,
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => EntryTile(
                        entry: list[i],
                        onTap: () => context.push(
                          '/space/$spaceId/party/$partyId/entry/${list[i].id}',
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setReminder(BuildContext context, WidgetRef ref) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    await ref.read(ledgerRepositoryProvider).setReminder(spaceId, partyId, d);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).saved)),
      );
    }
  }
}

class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.onTap});
  final Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final gave = entry.direction == EntryDirection.gave;
    final color = entry.isVoided
        ? scheme.onSurfaceVariant
        : MoneyText.colorFor(context, gave);
    final strike = entry.isVoided ? TextDecoration.lineThrough : null;
    final subtitle = [
      friendlyDate(context, entry.entryDate),
      if (entry.isReversal)
        l.reversalNote
      else if (entry.note != null)
        entry.note!,
      if (entry.isVoided) l.cancelled else if (entry.wasEdited) l.edited,
    ].join('  ·  ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: Tokens.s1),
      onTap: onTap,
      leading: Icon(
        gave ? Icons.arrow_outward_rounded : Icons.call_received_rounded,
        color: color,
      ),
      title: Text(
        gave ? l.gave : l.got,
        style: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          decoration: strike,
        ),
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        'Rs ${Money.format(entry.amountPaisa)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 17,
          decoration: strike,
          fontFamily: 'Roboto',
        ),
      ),
    );
  }
}
