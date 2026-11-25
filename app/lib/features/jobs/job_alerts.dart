/// How many alerts a job gives. "New job" always goes out; this decides the
/// rest. The same levels are worked out on the server by job_alert_plan.
enum AlertLevel { few, normal, many, custom }

class JobAlerts {
  const JobAlerts(
    this.level, {
    this.repeats = 1,
    this.every = 30,
    this.evening = true,
    this.before = const [60],
    this.updates = true,
  });

  const JobAlerts.few()
    : this(
        AlertLevel.few,
        repeats: 0,
        evening: false,
        before: const [],
        updates: false,
      );
  const JobAlerts.normal() : this(AlertLevel.normal);
  const JobAlerts.many()
    : this(AlertLevel.many, repeats: 3, every: 15, before: const [60, 15]);

  final AlertLevel level;

  /// Reminders when nobody has confirmed, and the minutes between them.
  final int repeats;
  final int every;

  /// One on the evening before the job.
  final bool evening;

  /// Minutes before the job starts.
  final List<int> before;

  /// Tell owners and managers about confirmed, on the way and started.
  final bool updates;

  /// The most alerts one installer gets for a job.
  int get forInstaller => 1 + repeats + (evening ? 1 : 0) + before.length;

  /// The most an owner or manager gets: reminders, steps, and finished.
  int get forManager => repeats + (evening ? 1 : 0) + (updates ? 3 : 0) + 1;

  JobAlerts custom({
    int? repeats,
    int? every,
    bool? evening,
    List<int>? before,
    bool? updates,
  }) => JobAlerts(
    AlertLevel.custom,
    repeats: repeats ?? this.repeats,
    every: every ?? this.every,
    evening: evening ?? this.evening,
    before: before ?? this.before,
    updates: updates ?? this.updates,
  );

  Map<String, dynamic> toJson() => {
    'level': level.name,
    if (level == AlertLevel.custom) ...{
      'repeats': repeats,
      'every': every,
      'evening': evening,
      'before': before,
      'updates': updates,
    },
  };

  /// Null when nothing is set, so the business default applies.
  static JobAlerts? fromJson(Object? j) {
    if (j is! Map) return null;
    switch (j['level']) {
      case 'few':
        return const JobAlerts.few();
      case 'many':
        return const JobAlerts.many();
      case 'custom':
        int n(String k, int or) => (j[k] as num?)?.toInt() ?? or;
        return JobAlerts(
          AlertLevel.custom,
          repeats: n('repeats', 1),
          every: n('every', 30),
          evening: j['evening'] as bool? ?? true,
          before: [
            for (final m in (j['before'] as List? ?? const []))
              (m as num).toInt(),
          ],
          updates: j['updates'] as bool? ?? true,
        );
      default:
        return const JobAlerts.normal();
    }
  }
}
