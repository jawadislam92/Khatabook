import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_repository.dart';
import '../groups/role_labels.dart';
import '../ledger/space_home_screen.dart';
import '../spaces/spaces_repository.dart';
import 'catalog_screen.dart';
import 'job_card.dart';
import 'jobs_models.dart';
import 'jobs_repository.dart';

/// Business space: Today, Jobs, Ledger, Catalog. Installers see their own jobs on Today.
class BusinessHomeScreen extends ConsumerStatefulWidget {
  const BusinessHomeScreen({
    super.key,
    required this.spaceId,
    this.initialTab = 0,
  });
  final String spaceId;
  final int initialTab;

  @override
  ConsumerState<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends ConsumerState<BusinessHomeScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == widget.spaceId)
        .firstOrNull;
    final manager = roleAtLeast(
      space?.myRole ?? MemberRole.viewer,
      MemberRole.manager,
    );
    final pages = [
      _TodayTab(
        spaceId: widget.spaceId,
        manager: manager,
        spaceName: space?.name ?? '',
      ),
      _JobsTab(spaceId: widget.spaceId),
      SpaceHomeScreen(spaceId: widget.spaceId, embedded: true),
      CatalogScreen(spaceId: widget.spaceId, embedded: true),
    ];
    return Scaffold(
      body: pages[_tab],
      floatingActionButton: manager && _tab < 2
          ? FloatingActionButton.extended(
              heroTag: 'new-job',
              onPressed: () => context.push('/space/${widget.spaceId}/job/new'),
              icon: const Icon(Icons.add_task),
              label: Text(l.newJob),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: manager ? l.tabToday : l.tabMyJobs,
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: l.tabJobs,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l.tabLedger,
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            label: l.tabCatalog,
          ),
        ],
      ),
    );
  }
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab({
    required this.spaceId,
    required this.manager,
    required this.spaceName,
  });
  final String spaceId;
  final bool manager;
  final String spaceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final me = ref.watch(currentUserProvider).value?.id ?? '';
    final all = ref.watch(jobsProvider(spaceId));
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return Scaffold(
      appBar: AppBar(
        title: Text(spaceName),
        actions: [
          IconButton(
            tooltip: l.notifications,
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            tooltip: l.members,
            icon: const Icon(Icons.group_outlined),
            onPressed: () => context.push('/space/$spaceId/members'),
          ),
        ],
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric)),
        data: (jobs) {
          final mine = manager
              ? jobs
              : jobs.where((j) => j.isAssignedTo(me)).toList();
          final open = mine.where((j) => j.status.isOpen).toList();
          final todays = open
              .where(
                (j) =>
                    !j.scheduledAt.isBefore(today) &&
                    j.scheduledAt.isBefore(tomorrow),
              )
              .toList();
          final overdue = open
              .where(
                (j) =>
                    j.scheduledAt.isBefore(today) &&
                    j.status != JobStatus.finished,
              )
              .toList();
          final upcoming = open
              .where((j) => !j.scheduledAt.isBefore(tomorrow))
              .take(5)
              .toList();
          Widget section(String title, List<Job> list, {bool date = false}) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      Tokens.s4,
                      0,
                      Tokens.s2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(l.jobsCount(list.length), style: text.bodySmall),
                      ],
                    ),
                  ),
                  for (final j in list) ...[
                    JobCard(
                      job: j,
                      showDate: date,
                      onTap: () => context.push('/space/$spaceId/job/${j.id}'),
                    ),
                    const SizedBox(height: Tokens.s2),
                  ],
                ],
              );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              0,
              Tokens.s4,
              Tokens.s7 * 2,
            ),
            children: [
              Text(
                DateFormat.yMMMMEEEEd(locale).format(now),
                style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (overdue.isNotEmpty) section(l.earlier, overdue, date: true),
              section(l.today, todays),
              if (todays.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Tokens.s3),
                  child: Text(
                    manager ? l.noJobsToday : l.noMyJobs,
                    style: text.bodyLarge,
                  ),
                ),
              if (upcoming.isNotEmpty) section(l.later, upcoming, date: true),
            ],
          );
        },
      ),
    );
  }
}

class _JobsTab extends ConsumerStatefulWidget {
  const _JobsTab({required this.spaceId});
  final String spaceId;
  @override
  ConsumerState<_JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends ConsumerState<_JobsTab> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final all = ref.watch(jobsProvider(widget.spaceId));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabJobs),
        actions: [
          FilterChip(
            label: Text(l.statusFinished),
            selected: _showClosed,
            onSelected: (v) => setState(() => _showClosed = v),
          ),
          const SizedBox(width: Tokens.s3),
        ],
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorGeneric)),
        data: (jobs) {
          final list =
              (_showClosed
                      ? jobs.where(
                          (j) =>
                              !j.status.isOpen ||
                              j.status == JobStatus.finished,
                        )
                      : jobs.where(
                          (j) =>
                              j.status.isOpen && j.status != JobStatus.finished,
                        ))
                  .toList();
          list.sort(
            (a, b) => _showClosed
                ? b.scheduledAt.compareTo(a.scheduledAt)
                : a.scheduledAt.compareTo(b.scheduledAt),
          );
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Tokens.s5),
                child: Text(
                  l.noJobs,
                  style: text.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Tokens.s4,
              Tokens.s2,
              Tokens.s4,
              Tokens.s7 * 2,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: Tokens.s2),
            itemBuilder: (_, i) => JobCard(
              job: list[i],
              showDate: true,
              onTap: () =>
                  context.push('/space/${widget.spaceId}/job/${list[i].id}'),
            ),
          );
        },
      ),
    );
  }
}
