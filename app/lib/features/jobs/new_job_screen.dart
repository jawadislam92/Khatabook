import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/big_button.dart';
import '../../core/widgets/load_error.dart';
import '../../core/utils/dates.dart';
import '../../l10n/app_localizations.dart';
import '../groups/groups_repository.dart';
import '../ledger/ledger_repository.dart';
import '../ledger/party_form.dart';
import 'job_labels.dart';
import 'jobs_models.dart';
import 'jobs_repository.dart';

class NewJobScreen extends ConsumerStatefulWidget {
  const NewJobScreen({super.key, required this.spaceId});
  final String spaceId;
  @override
  ConsumerState<NewJobScreen> createState() => _NewJobScreenState();
}

class _NewJobScreenState extends ConsumerState<NewJobScreen> {
  String? _customerId;
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _estimate = TextEditingController();
  JobType _type = JobType.cctvRepair;
  DateTime _when = () {
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 10);
  }();
  final _who = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _address.dispose();
    _notes.dispose();
    _estimate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final partiesLoad = ref.watch(partyBalancesProvider(widget.spaceId));
    final membersLoad = ref.watch(membersProvider(widget.spaceId));
    final parties = partiesLoad.value ?? const [];
    final members = membersLoad.value ?? const [];
    final customer = parties
        .where((p) => p.party.id == _customerId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(l.newJob)),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.s4),
        children: [
          // Without these two lists there is no customer or person to pick.
          if (partiesLoad.failed || membersLoad.failed)
            LoadError(
              onRetry: () {
                ref.invalidate(partyBalancesProvider(widget.spaceId));
                ref.invalidate(membersProvider(widget.spaceId));
              },
            ),
          Text(l.customer, style: text.labelLarge),
          const SizedBox(height: Tokens.s1),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(customer?.party.name ?? l.pickCustomer),
              subtitle: customer?.party.phone == null
                  ? null
                  : Text(customer!.party.phone!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickCustomer(parties),
            ),
          ),
          const SizedBox(height: Tokens.s4),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.jobTitle,
              hintText: l.jobTitleHint,
            ),
          ),
          const SizedBox(height: Tokens.s4),
          Text(l.jobType, style: text.labelLarge),
          const SizedBox(height: Tokens.s1),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: [
              for (final t in JobType.values)
                ChoiceChip(
                  avatar: Icon(jobTypeIcon(t), size: 18),
                  label: Text(jobTypeLabel(l, t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Text(l.whenLabel, style: text.labelLarge),
          const SizedBox(height: Tokens.s1),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(DateFormat.MMMEd(locale).format(_when)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _when,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      setState(
                        () => _when = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          _when.hour,
                          _when.minute,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: Tokens.s2),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(clockTime(context, _when)),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_when),
                    );
                    if (t != null) {
                      setState(
                        () => _when = DateTime(
                          _when.year,
                          _when.month,
                          _when.day,
                          t.hour,
                          t.minute,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          Text(l.whoGoes, style: text.labelLarge),
          const SizedBox(height: Tokens.s1),
          Wrap(
            spacing: Tokens.s2,
            runSpacing: Tokens.s2,
            children: [
              for (final m in members)
                FilterChip(
                  avatar: CircleAvatar(
                    child: Text(m.name.isEmpty ? '?' : m.name.substring(0, 1)),
                  ),
                  label: Text(m.name),
                  selected: _who.contains(m.userId),
                  onSelected: (v) => setState(
                    () => v ? _who.add(m.userId) : _who.remove(m.userId),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.s4),
          TextField(
            controller: _address,
            decoration: InputDecoration(
              labelText: l.addressOptional,
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: Tokens.s3),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: l.notesOptional),
          ),
          const SizedBox(height: Tokens.s3),
          TextField(
            controller: _estimate,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.estimateOptional,
              prefixText: 'Rs ',
            ),
          ),
          const SizedBox(height: Tokens.s5),
          BigButton(
            label: l.save,
            icon: Icons.check,
            busy: _busy,
            onPressed: _customerId == null || _title.text.trim().isEmpty
                ? null
                : _save,
          ),
          const SizedBox(height: Tokens.s6),
        ],
      ),
    );
  }

  Future<void> _pickCustomer(List parties) async {
    final l = AppLocalizations.of(context);
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            Tokens.s4,
            0,
            Tokens.s4,
            Tokens.s4,
          ),
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Tokens.saffron,
                child: Icon(Icons.person_add_alt_1, color: Colors.black),
              ),
              title: Text(l.newCustomer),
              onTap: () async {
                final p = await showPartyForm(
                  ctx,
                  ref,
                  spaceId: widget.spaceId,
                );
                if (p != null && ctx.mounted) Navigator.pop(ctx, p.id);
              },
            ),
            for (final pb in parties)
              ListTile(
                leading: CircleAvatar(child: Text(pb.party.initials)),
                title: Text(pb.party.name),
                subtitle: Text(
                  [
                    if (pb.party.phone != null) pb.party.phone!,
                    if (pb.balancePaisa > 0)
                      '${l.youWillGet} Rs ${Money.format(pb.balancePaisa)}',
                    if (pb.balancePaisa < 0)
                      '${l.youWillGive} Rs ${Money.format(-pb.balancePaisa)}',
                    if (pb.party.phone == null && pb.balancePaisa == 0)
                      l.settled,
                  ].join('  ·  '),
                ),
                onTap: () => Navigator.pop(ctx, pb.party.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) setState(() => _customerId = id);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(jobsRepositoryProvider)
          .createJob(
            NewJob(
              spaceId: widget.spaceId,
              customerId: _customerId!,
              title: _title.text,
              type: _type,
              scheduledAt: _when,
              assigneeIds: _who.toList(),
              address: _address.text.trim().isEmpty
                  ? null
                  : _address.text.trim(),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              estimatePaisa: Money.parse(_estimate.text),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.jobCreated)));
      context.pushReplacement('/space/${widget.spaceId}/job/$id');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorGeneric)));
      }
    }
  }
}
