import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/money_text.dart';
import '../../l10n/app_localizations.dart';
import '../groups/groups_models.dart';
import '../groups/groups_repository.dart';
import '../groups/role_labels.dart';
import '../spaces/spaces_repository.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'party_form.dart';
import 'share_actions.dart';

/// Home of one space: totals, the two big actions, reminders, and people.
class SpaceHomeScreen extends ConsumerStatefulWidget {
  const SpaceHomeScreen({
    super.key,
    required this.spaceId,
    this.embedded = false,
  });
  final String spaceId;
  final bool embedded;

  @override
  ConsumerState<SpaceHomeScreen> createState() => _SpaceHomeScreenState();
}

class _SpaceHomeScreenState extends ConsumerState<SpaceHomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final simple = ref.watch(appSettingsProvider).simpleMode;
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == widget.spaceId)
        .firstOrNull;
    final spaceName = space == null
        ? ''
        : (space.kind == SpaceKind.personal ? l.spacePersonal : space.name);
    final totalsLoad = ref.watch(spaceTotalsProvider(widget.spaceId));
    final totals = totalsLoad.value ?? SpaceTotals.zero;
    final parties = ref.watch(partyBalancesProvider(widget.spaceId));
    final remindersLoad = ref.watch(remindersProvider(widget.spaceId));
    final reminders = remindersLoad.value ?? const <Reminder>[];
    void retry() {
      ref.invalidate(partyBalancesProvider(widget.spaceId));
      ref.invalidate(spaceTotalsProvider(widget.spaceId));
      ref.invalidate(remindersProvider(widget.spaceId));
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hue = switch ((space?.kind, space?.businessEnabled)) {
      (SpaceKind.personal, _) => Tokens.personalHue,
      (SpaceKind.group, true) => Tokens.businessHue,
      _ => Tokens.familyHue,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.embedded ? l.tabLedger : spaceName),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (space != null && space.kind == SpaceKind.group) ...[
            IconButton(
              tooltip: l.activity,
              icon: const Icon(Icons.history),
              onPressed: () =>
                  context.push('/space/${widget.spaceId}/activity'),
            ),
            IconButton(
              tooltip: l.members,
              icon: const Icon(Icons.group_outlined),
              onPressed: () => context.push('/space/${widget.spaceId}/members'),
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'csv') shareCsv(context, ref, widget.spaceId, spaceName);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(l.exportCsv),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-party',
        onPressed: () async {
          final p = await showPartyForm(context, ref, spaceId: widget.spaceId);
          if (p != null && context.mounted) {
            context.push('/space/${widget.spaceId}/party/${p.id}');
          }
        },
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(l.newPerson),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(partyBalancesProvider(widget.spaceId));
          ref.invalidate(spaceTotalsProvider(widget.spaceId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            Tokens.s7 * 2,
          ),
          children: [
            // Zero totals after a failed request would read as "nothing due".
            if (totalsLoad.failed || remindersLoad.failed)
              LoadError(onRetry: retry),
            if (!totalsLoad.failed)
              _TotalsCard(totals: totals, hue: hue, simple: simple),
            const SizedBox(height: Tokens.s3),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: l.iGaveMoney,
                    icon: Icons.arrow_outward_rounded,
                    color: MoneyText.colorFor(context, true),
                    onTap: () => context.push(
                      '/space/${widget.spaceId}/add?direction=gave',
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.s3),
                Expanded(
                  child: _ActionButton(
                    label: l.iGotMoney,
                    icon: Icons.call_received_rounded,
                    color: MoneyText.colorFor(context, false),
                    onTap: () => context.push(
                      '/space/${widget.spaceId}/add?direction=got',
                    ),
                  ),
                ),
              ],
            ),
            if (space != null && space.kind == SpaceKind.group) ...[
              const SizedBox(height: Tokens.s5),
              _ByMember(spaceId: widget.spaceId),
            ],
            if (reminders.isNotEmpty) ...[
              const SizedBox(height: Tokens.s5),
              Text(
                l.reminders,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: Tokens.s2),
              for (final r in reminders)
                _ReminderTile(
                  reminder: r,
                  spaceId: widget.spaceId,
                  parties: parties.value ?? const [],
                ),
            ],
            const SizedBox(height: Tokens.s5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.people,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if ((parties.value?.length ?? 0) > 0)
                  Text(
                    '${parties.value!.length}',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s2),
            if ((parties.value?.length ?? 0) > 4) ...[
              TextField(
                controller: _search,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: l.searchPeople,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: Tokens.s3),
            ],
            parties.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Tokens.s6),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => LoadError(onRetry: retry),
              data: (list) {
                final filtered = _query.isEmpty
                    ? list
                    : list
                          .where(
                            (p) => p.party.name.toLowerCase().contains(_query),
                          )
                          .toList();
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(Tokens.s5),
                    child: Text(
                      l.noPeopleYet,
                      textAlign: TextAlign.center,
                      style: text.bodyLarge,
                    ),
                  );
                }
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(Tokens.s5),
                    child: Text(l.noMatches, textAlign: TextAlign.center),
                  );
                }
                // Active balances first, then settled, each alphabetically.
                final sorted = [...filtered]
                  ..sort((a, b) {
                    final s = (a.settled ? 1 : 0) - (b.settled ? 1 : 0);
                    return s != 0
                        ? s
                        : a.party.name.toLowerCase().compareTo(
                            b.party.name.toLowerCase(),
                          );
                  });
                return Column(
                  children: [
                    for (final pb in sorted) ...[
                      PartyTile(
                        pb: pb,
                        onTap: () => context.push(
                          '/space/${widget.spaceId}/party/${pb.party.id}',
                        ),
                      ),
                      const SizedBox(height: Tokens.s2),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.totals,
    required this.hue,
    required this.simple,
  });
  final SpaceTotals totals;
  final Color hue;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget tile(String label, int paisa, bool sign) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Tokens.s4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(Tokens.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sign ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 18,
                  color: MoneyText.colorFor(context, sign),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: Tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(brightness: Brightness.light),
              child: MoneyText(
                paisa: paisa,
                sign: sign,
                size: simple ? 26 : 22,
                words: simple,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(Tokens.s3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [hue, Color.lerp(hue, Tokens.indigoDeep, 0.5)!],
        ),
        borderRadius: BorderRadius.circular(Tokens.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: hue.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          tile(l.youWillGet, totals.willGetPaisa, true),
          const SizedBox(width: Tokens.s3),
          tile(l.youWillGive, totals.willGivePaisa, false),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final simple = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: Size(double.infinity, simple ? 72 : 60),
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.s3,
          vertical: Tokens.s3,
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 26),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

class PartyTile extends StatelessWidget {
  const PartyTile({super.key, required this.pb, required this.onTap});
  final PartyBalance pb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sign = pb.settled ? null : pb.willGet;
    final hue = pb.settled ? scheme.outline : MoneyText.colorFor(context, sign);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s3,
            vertical: Tokens.s3,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: hue.withValues(alpha: 0.15),
                child: Text(
                  pb.party.initials,
                  style: TextStyle(
                    color: hue,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
              const SizedBox(width: Tokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pb.party.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      pb.settled
                          ? l.settled
                          : (pb.lastEntryDate == null
                                ? ''
                                : friendlyDate(context, pb.lastEntryDate!)),
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.s2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    paisa: pb.balancePaisa,
                    sign: sign,
                    size: 18,
                    align: TextAlign.end,
                  ),
                  Text(
                    pb.settled
                        ? l.nothingDue
                        : (pb.willGet ? l.youWillGet : l.youWillGive),
                    style: text.labelSmall?.copyWith(
                      color: hue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({
    required this.reminder,
    required this.spaceId,
    required this.parties,
  });
  final Reminder reminder;
  final String spaceId;
  final List<PartyBalance> parties;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pb = parties.where((p) => p.party.id == reminder.partyId).firstOrNull;
    if (pb == null) return const SizedBox.shrink();
    final overdue = reminder.dueDate.isBefore(DateTime.now());
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.alarm,
          color: overdue ? Tokens.give : Tokens.saffronDeep,
        ),
        title: Text(pb.party.name),
        subtitle: Text(
          '${l.reminderDue(friendlyDate(context, reminder.dueDate))}  ·  Rs ${pb.balancePaisa.abs() ~/ 100}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: l.sendWhatsApp,
              icon: const Icon(Icons.chat_outlined),
              onPressed: () => sendReminderMessage(context, pb),
            ),
            IconButton(
              tooltip: l.markDone,
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => ref
                  .read(ledgerRepositoryProvider)
                  .markReminderDone(reminder.id),
            ),
          ],
        ),
        onTap: () => context.push('/space/$spaceId/party/${pb.party.id}'),
      ),
    );
  }
}

class _ByMember extends ConsumerWidget {
  const _ByMember({required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final membersLoad = ref.watch(membersProvider(spaceId));
    if (membersLoad.failed) {
      return LoadError(onRetry: () => ref.invalidate(membersProvider(spaceId)));
    }
    final members = membersLoad.value ?? const <Member>[];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final active = members.where((m) => m.entriesCount > 0).toList()
      ..sort((a, b) => b.entriesCount.compareTo(a.entriesCount));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.byMember,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/space/$spaceId/members'),
              child: Text(l.members),
            ),
          ],
        ),
        const SizedBox(height: Tokens.s2),
        if (active.isEmpty)
          Text(
            l.noActivity,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: active.length,
              separatorBuilder: (_, _) => const SizedBox(width: Tokens.s2),
              itemBuilder: (_, i) {
                final m = active[i];
                return Container(
                  width: 168,
                  padding: const EdgeInsets.all(Tokens.s3),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(Tokens.radius),
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        m.name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${roleLabel(l, m.role)}  ·  ${l.entriesByMember(m.entriesCount)}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: MoneyText.colorFor(context, true),
                          ),
                          Flexible(
                            child: Text(
                              ' ${m.gavePaisa ~/ 100}  ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                          Icon(
                            Icons.call_received_rounded,
                            size: 14,
                            color: MoneyText.colorFor(context, false),
                          ),
                          Flexible(
                            child: Text(
                              ' ${m.gotPaisa ~/ 100}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
