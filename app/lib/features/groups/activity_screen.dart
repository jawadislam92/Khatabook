import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/load_error.dart';
import '../../core/widgets/money_text.dart';
import '../../l10n/app_localizations.dart';
import 'groups_models.dart';
import 'groups_repository.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.spaceId});
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(activityProvider(spaceId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(title: Text(l.activity)),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            LoadError(onRetry: () => ref.invalidate(activityProvider(spaceId))),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Tokens.s5),
                  child: Text(l.noActivity, style: text.bodyLarge),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Tokens.s4),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = list[i];
                  final actor = a.actorName ?? '';
                  final (icon, color, line) = switch (a.kind) {
                    ActivityKind.entryAdded => (
                      a.direction == 'gave'
                          ? Icons.arrow_outward_rounded
                          : Icons.call_received_rounded,
                      MoneyText.colorFor(context, a.direction == 'gave'),
                      l.activityAdded(
                        actor,
                        Money.format(a.amountPaisa ?? 0),
                        a.direction == 'gave' ? l.givenTo : l.receivedFrom,
                        a.partyName ?? '',
                      ),
                    ),
                    ActivityKind.entryCancelled => (
                      Icons.block,
                      scheme.onSurfaceVariant,
                      l.activityCancelled(
                        actor,
                        Money.format(a.amountPaisa ?? 0),
                        a.partyName ?? '',
                      ),
                    ),
                    ActivityKind.memberJoined => (
                      Icons.person_add_alt_1_outlined,
                      Tokens.indigo,
                      l.activityJoined(actor),
                    ),
                  };
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(line),
                    subtitle: Text(
                      DateFormat.yMMMd(locale).add_jm().format(a.at.toLocal()),
                    ),
                    onTap: a.partyId == null
                        ? null
                        : () => context.push(
                            '/space/$spaceId/party/${a.partyId}',
                          ),
                  );
                },
              ),
      ),
    );
  }
}
