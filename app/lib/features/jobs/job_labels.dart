import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'jobs_models.dart';

String jobTypeLabel(AppLocalizations l, JobType t) => switch (t) {
  JobType.cctvInstall => l.jobTypeCctvInstall,
  JobType.cctvRepair => l.jobTypeCctvRepair,
  JobType.solarInstall => l.jobTypeSolarInstall,
  JobType.solarService => l.jobTypeSolarService,
  JobType.other => l.jobTypeOther,
};

IconData jobTypeIcon(JobType t) => switch (t) {
  JobType.cctvInstall || JobType.cctvRepair => Icons.videocam_outlined,
  JobType.solarInstall || JobType.solarService => Icons.solar_power_outlined,
  JobType.other => Icons.build_outlined,
};

String statusLabel(AppLocalizations l, JobStatus s) => switch (s) {
  JobStatus.scheduled => l.statusScheduled,
  JobStatus.confirmed => l.statusConfirmed,
  JobStatus.onTheWay => l.statusOnTheWay,
  JobStatus.working => l.statusWorking,
  JobStatus.onHold => l.statusOnHold,
  JobStatus.finished => l.statusFinished,
  JobStatus.invoiced => l.statusInvoiced,
  JobStatus.paid => l.statusPaid,
  JobStatus.cancelled => l.statusCancelled,
};

Color statusColor(JobStatus s) => switch (s) {
  JobStatus.scheduled => Tokens.muted,
  JobStatus.confirmed => Tokens.sky,
  JobStatus.onTheWay => Tokens.indigo,
  JobStatus.working => Tokens.violet,
  JobStatus.onHold => Tokens.rose,
  JobStatus.finished => Tokens.get,
  JobStatus.invoiced => Tokens.saffronDeep,
  JobStatus.paid => Tokens.primary,
  JobStatus.cancelled => Tokens.give,
};

String categoryLabel(AppLocalizations l, String c) => switch (c) {
  'camera' => l.catCamera,
  'dvr' => l.catDvr,
  'cable' => l.catCable,
  'accessory' => l.catAccessory,
  'solar_panel' => l.catSolarPanel,
  'inverter' => l.catInverter,
  'battery' => l.catBattery,
  'structure' => l.catStructure,
  'wiring' => l.catWiring,
  'labour' => l.catLabour,
  'visit' => l.catVisit,
  _ => l.catOther,
};

String unitLabel(AppLocalizations l, String u) => switch (u) {
  'pc' => l.unitPc,
  'm' => l.unitM,
  'set' => l.unitSet,
  'hour' => l.unitHour,
  'visit' => l.unitVisit,
  'kg' => l.unitKg,
  'box' => l.unitBox,
  _ => u,
};

String holdReasonLabel(AppLocalizations l, String r) => switch (r) {
  'no_power' => l.holdNoPower,
  'customer_away' => l.holdCustomerAway,
  'parts_missing' => l.holdPartsMissing,
  'weather' => l.holdWeather,
  _ => l.holdOther,
};
