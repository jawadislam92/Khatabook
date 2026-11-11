import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/dates.dart';
import '../../l10n/app_localizations.dart';
import 'job_labels.dart';
import 'jobs_models.dart';

/// One job in a list: time, customer, title, who, status.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.showDate = false,
  });
  final Job job;
  final VoidCallback onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final color = statusColor(job.status);
    final late =
        job.status.isOpen &&
        job.status != JobStatus.finished &&
        job.status != JobStatus.onHold &&
        job.scheduledAt.isBefore(
          DateTime.now().subtract(const Duration(minutes: 30)),
        );
    final time = clockTime(context, job.scheduledAt);
    final date = DateFormat.MMMEd(locale).format(job.scheduledAt);
    final who = job.assignees.map((a) => a.name).join(', ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(Tokens.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Large text (simple mode) must not push the
                          // status chips off the card.
                          Expanded(
                            child: Text(
                              showDate ? '$date  $time' : time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Chip(
                            label: statusLabel(l, job.status),
                            color: color,
                          ),
                          if (job.status == JobStatus.finished) ...[
                            const SizedBox(width: 6),
                            _Chip(
                              label: l.billNeeded,
                              color: Tokens.saffronDeep,
                            ),
                          ],
                          if (late) ...[
                            const SizedBox(width: 6),
                            _Chip(label: l.lateJob, color: Tokens.give),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        job.customerName,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        job.title,
                        style: text.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            jobTypeIcon(job.type),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            jobTypeLabel(l, job.type),
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: Tokens.s3),
                          Icon(
                            Icons.people_outline,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              who.isEmpty ? l.nobodyAssigned : who,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (job.status == JobStatus.scheduled &&
                              !job.anyoneConfirmed &&
                              job.assignees.isNotEmpty)
                            Icon(
                              Icons.hourglass_top,
                              size: 16,
                              color: Tokens.saffronDeep,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w700),
    ),
  );
}
