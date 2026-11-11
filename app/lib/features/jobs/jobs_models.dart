enum JobType { cctvInstall, cctvRepair, solarInstall, solarService, other }

enum JobStatus {
  scheduled,
  confirmed,
  onTheWay,
  working,

  /// Stopped on site (no power, customer away...). Waits for a new date.
  onHold,
  finished,
  invoiced,
  paid,
  cancelled,
}

extension JobTypeDb on JobType {
  String get db => switch (this) {
    JobType.cctvInstall => 'cctv_install',
    JobType.cctvRepair => 'cctv_repair',
    JobType.solarInstall => 'solar_install',
    JobType.solarService => 'solar_service',
    JobType.other => 'other',
  };
  static JobType fromDb(String s) =>
      JobType.values.firstWhere((t) => t.db == s, orElse: () => JobType.other);
}

extension JobStatusDb on JobStatus {
  String get db => switch (this) {
    JobStatus.scheduled => 'scheduled',
    JobStatus.confirmed => 'confirmed',
    JobStatus.onTheWay => 'on_the_way',
    JobStatus.working => 'working',
    JobStatus.onHold => 'on_hold',
    JobStatus.finished => 'finished',
    JobStatus.invoiced => 'invoiced',
    JobStatus.paid => 'paid',
    JobStatus.cancelled => 'cancelled',
  };
  static JobStatus fromDb(String s) => JobStatus.values.firstWhere(
    (t) => t.db == s,
    orElse: () => JobStatus.scheduled,
  );
  bool get isOpen =>
      this != JobStatus.cancelled &&
      this != JobStatus.paid &&
      this != JobStatus.invoiced;
}

class JobAssignee {
  const JobAssignee({
    required this.userId,
    required this.name,
    this.confirmedAt,
  });
  final String userId;
  final String name;
  final DateTime? confirmedAt;
  bool get confirmed => confirmedAt != null;
}

class Job {
  const Job({
    required this.id,
    required this.spaceId,
    required this.customerId,
    required this.customerName,
    required this.title,
    required this.type,
    required this.scheduledAt,
    required this.status,
    required this.assignees,
    required this.createdBy,
    required this.createdAt,
    this.customerPhone,
    this.address,
    this.notes,
    this.estimatePaisa,
    this.holdReason,
    this.holdNote,
    this.suggestedAt,
  });
  final String id;
  final String spaceId;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String title;
  final JobType type;
  final DateTime scheduledAt;
  final String? address;
  final String? notes;
  final int? estimatePaisa;
  final JobStatus status;
  final List<JobAssignee> assignees;
  final String createdBy;
  final DateTime createdAt;

  /// Why the job was stopped on site: one of [holdReasons], or null.
  final String? holdReason;
  final String? holdNote;

  /// The date the installer suggested for the next visit.
  final DateTime? suggestedAt;

  bool isAssignedTo(String userId) => assignees.any((a) => a.userId == userId);
  bool get anyoneConfirmed => assignees.any((a) => a.confirmed);
  bool get isToday {
    final n = DateTime.now();
    final s = scheduledAt.toLocal();
    return s.year == n.year && s.month == n.month && s.day == n.day;
  }

  Job copyWith({
    JobStatus? status,
    List<JobAssignee>? assignees,
    DateTime? scheduledAt,
  }) => Job(
    id: id,
    spaceId: spaceId,
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerPhone,
    title: title,
    type: type,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    address: address,
    notes: notes,
    estimatePaisa: estimatePaisa,
    status: status ?? this.status,
    assignees: assignees ?? this.assignees,
    createdBy: createdBy,
    createdAt: createdAt,
    holdReason: status == null || status == JobStatus.onHold
        ? holdReason
        : null,
    holdNote: status == null || status == JobStatus.onHold ? holdNote : null,
    suggestedAt: status == null || status == JobStatus.onHold
        ? suggestedAt
        : null,
  );

  /// The same job stopped on site.
  Job onHoldWith({String? reason, String? note, DateTime? suggested}) => Job(
    id: id,
    spaceId: spaceId,
    customerId: customerId,
    customerName: customerName,
    customerPhone: customerPhone,
    title: title,
    type: type,
    scheduledAt: scheduledAt,
    address: address,
    notes: notes,
    estimatePaisa: estimatePaisa,
    status: JobStatus.onHold,
    assignees: assignees,
    createdBy: createdBy,
    createdAt: createdAt,
    holdReason: reason,
    holdNote: note,
    suggestedAt: suggested,
  );
}

/// Reasons an installer can give for stopping a job, as stored on the server.
const holdReasons = [
  'no_power',
  'customer_away',
  'parts_missing',
  'weather',
  'other',
];

class JobEvent {
  const JobEvent({
    required this.at,
    required this.type,
    this.fromStatus,
    this.toStatus,
    this.actorName,
    this.note,
  });
  final DateTime at;
  final String type;
  final JobStatus? fromStatus;
  final JobStatus? toStatus;
  final String? actorName;
  final String? note;
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.spaceId,
    required this.nameEn,
    required this.unit,
    required this.category,
    required this.salePricePaisa,
    this.nameUr,
    this.costPricePaisa,
    this.isFavourite = false,
    this.allowPriceEdit = false,
    this.active = true,
  });
  final String id;
  final String spaceId;
  final String nameEn;
  final String? nameUr;
  final String unit;
  final String category;
  final int salePricePaisa;
  final int? costPricePaisa;
  final bool isFavourite;
  final bool allowPriceEdit;
  final bool active;

  String name(String lang) =>
      lang == 'ur' && (nameUr?.isNotEmpty ?? false) ? nameUr! : nameEn;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.deepLink,
    this.readAt,
  });
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? deepLink;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get unread => readAt == null;
}

class NewJob {
  const NewJob({
    required this.spaceId,
    required this.customerId,
    required this.title,
    required this.type,
    required this.scheduledAt,
    required this.assigneeIds,
    this.address,
    this.notes,
    this.estimatePaisa,
  });
  final String spaceId;
  final String customerId;
  final String title;
  final JobType type;
  final DateTime scheduledAt;
  final List<String> assigneeIds;
  final String? address;
  final String? notes;
  final int? estimatePaisa;
}

const itemCategories = [
  'camera',
  'dvr',
  'cable',
  'accessory',
  'solar_panel',
  'inverter',
  'battery',
  'structure',
  'wiring',
  'labour',
  'visit',
  'other',
];
const itemUnits = ['pc', 'm', 'set', 'hour', 'visit', 'kg', 'box'];
