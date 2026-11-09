import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/big_button.dart';
import '../../l10n/app_localizations.dart';
import '../groups/role_labels.dart';
import '../jobs/job_labels.dart';
import '../jobs/jobs_models.dart';
import '../jobs/jobs_repository.dart';
import '../spaces/spaces_repository.dart';
import 'invoice_models.dart';
import 'invoices_repository.dart';

/// Step one of finishing a job: what was used. Quick tiles for favourites,
/// a search for everything else, and a free text charge for the rest.
class FinishJobScreen extends ConsumerStatefulWidget {
  const FinishJobScreen({
    super.key,
    required this.spaceId,
    required this.jobId,
  });
  final String spaceId;
  final String jobId;

  @override
  ConsumerState<FinishJobScreen> createState() => _FinishJobScreenState();
}

class _FinishJobScreenState extends ConsumerState<FinishJobScreen> {
  final _lines = <JobItem>[];
  final _search = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(invoicesRepositoryProvider).jobItems(widget.jobId).then((items) {
      if (!mounted) return;
      setState(() {
        _lines.addAll(items);
        _loaded = true;
      });
    });
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _total => BillMath.subtotal(_lines);

  JobItem? _lineFor(CatalogItem item) =>
      _lines.where((l) => l.itemId == item.id).firstOrNull;

  void _add(CatalogItem item, {double step = 1}) {
    final existing = _lineFor(item);
    setState(() {
      if (existing == null) {
        _lines.add(
          JobItem(
            id: '',
            jobId: widget.jobId,
            itemId: item.id,
            description: item.nameEn,
            qty: step,
            unit: item.unit,
            unitPricePaisa: item.salePricePaisa,
          ),
        );
      } else {
        _setQty(existing, existing.qty + step);
      }
    });
    _search.clear();
  }

  void _setQty(JobItem line, double qty) {
    final i = _lines.indexOf(line);
    if (i < 0) return;
    if (qty <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i] = line.copyWith(qty: double.parse(qty.toStringAsFixed(3)));
    }
  }

  Future<void> _typeQty(JobItem line) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: formatQty(line.qty));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.description),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l.qty,
            suffixText: line.unit == null ? null : unitLabel(l, line.unit!),
          ),
          onSubmitted: (s) => Navigator.pop(ctx, double.tryParse(s)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
            child: Text(l.done),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _setQty(line, v));
  }

  Future<void> _editPrice(JobItem line) async {
    final l = AppLocalizations.of(context);
    final c = TextEditingController(text: Money.format(line.unitPricePaisa));
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.changePrice),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l.rate, prefixText: 'Rs '),
          onSubmitted: (s) => Navigator.pop(ctx, Money.parse(s)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, Money.parse(c.text)),
            child: Text(l.done),
          ),
        ],
      ),
    );
    if (v != null && v >= 0) {
      setState(() {
        final i = _lines.indexOf(line);
        _lines[i] = line.copyWith(unitPricePaisa: v);
      });
    }
  }

  Future<void> _otherCharge() async {
    final l = AppLocalizations.of(context);
    final desc = TextEditingController();
    final amt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.otherCharge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: desc,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l.description,
                hintText: l.otherChargeHint,
              ),
            ),
            const SizedBox(height: Tokens.s3),
            TextField(
              controller: amt,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.amount,
                prefixText: 'Rs ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.done),
          ),
        ],
      ),
    );
    final paisa = Money.parse(amt.text);
    if (ok == true &&
        desc.text.trim().isNotEmpty &&
        paisa != null &&
        paisa > 0) {
      setState(() {
        _lines.add(
          JobItem(
            id: '',
            jobId: widget.jobId,
            description: desc.text.trim(),
            qty: 1,
            unitPricePaisa: paisa,
          ),
        );
      });
    }
  }

  Future<bool> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(invoicesRepositoryProvider)
          .setJobItems(widget.spaceId, widget.jobId, _lines);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorGeneric)),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveOnly() async {
    if (await _save() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).itemsSaved)),
      );
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _next(Job job) async {
    if (!await _save()) return;
    if (job.status == JobStatus.working) {
      await ref
          .read(jobsRepositoryProvider)
          .setStatus(widget.jobId, JobStatus.finished);
    }
    if (!mounted) return;
    context.pushReplacement(
      '/space/${widget.spaceId}/job/${widget.jobId}/bill',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lang = Localizations.localeOf(context).languageCode;
    final job = ref.watch(jobProvider((widget.spaceId, widget.jobId))).value;
    final catalog =
        (ref.watch(catalogProvider(widget.spaceId)).value ?? const [])
            .where((i) => i.active)
            .toList();
    final space = ref
        .watch(mySpacesProvider)
        .value
        ?.where((s) => s.id == widget.spaceId)
        .firstOrNull;
    final manager = roleAtLeast(
      space?.myRole ?? MemberRole.viewer,
      MemberRole.manager,
    );
    final favourites = catalog.where((i) => i.isFavourite).toList();
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <CatalogItem>[]
        : catalog
              .where(
                (i) =>
                    i.nameEn.toLowerCase().contains(q) ||
                    (i.nameUr?.contains(q) ?? false) ||
                    categoryLabel(l, i.category).toLowerCase().contains(q),
              )
              .take(8)
              .toList();
    bool canEditPrice(JobItem line) {
      if (manager || line.itemId == null) return true;
      return catalog
              .where((i) => i.id == line.itemId)
              .firstOrNull
              ?.allowPriceEdit ??
          true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.itemsUsed),
        actions: [
          IconButton(
            tooltip: l.saveItems,
            icon: const Icon(Icons.save_outlined),
            onPressed: _busy || !_loaded ? null : _saveOnly,
          ),
        ],
      ),
      body: !_loaded || job == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                Tokens.s2,
                Tokens.s4,
                Tokens.s7 * 3,
              ),
              children: [
                Text(
                  '${job.customerName}  ·  ${job.title}',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (favourites.isNotEmpty) ...[
                  const SizedBox(height: Tokens.s4),
                  Text(
                    l.quickAdd,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Tokens.s2),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: Tokens.s2,
                          crossAxisSpacing: Tokens.s2,
                          mainAxisExtent: 112,
                        ),
                    itemCount: favourites.length,
                    itemBuilder: (_, i) => _QuickTile(
                      item: favourites[i],
                      line: _lineFor(favourites[i]),
                      lang: lang,
                      onAdd: () => _add(favourites[i]),
                      onRemove: () => setState(
                        () => _setQty(
                          _lineFor(favourites[i])!,
                          _lineFor(favourites[i])!.qty - 1,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Tokens.s4),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: l.searchItems,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _search.clear,
                          ),
                  ),
                ),
                for (final m in matches)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.name(lang)),
                    subtitle: Text(
                      'Rs ${Money.format(m.salePricePaisa)} / ${unitLabel(l, m.unit)}',
                    ),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => _add(m),
                  ),
                const SizedBox(height: Tokens.s2),
                OutlinedButton.icon(
                  onPressed: _otherCharge,
                  icon: const Icon(Icons.edit_note),
                  label: Text(l.otherCharge),
                ),
                const SizedBox(height: Tokens.s5),
                Text(
                  l.itemsUsed,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: Tokens.s2),
                if (_lines.isEmpty)
                  Text(
                    l.nothingAddedYet,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                for (final line in _lines)
                  _LineCard(
                    line: line,
                    canEditPrice: canEditPrice(line),
                    onMinus: () => setState(() => _setQty(line, line.qty - 1)),
                    onPlus: () => setState(() => _setQty(line, line.qty + 1)),
                    onQty: () => _typeQty(line),
                    onPrice: () => _editPrice(line),
                    onRemove: () => setState(() => _lines.remove(line)),
                  ),
              ],
            ),
      bottomNavigationBar: !_loaded || job == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s4,
                  Tokens.s3,
                  Tokens.s4,
                  Tokens.s3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          l.total,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Rs ${Money.format(_total)}',
                          style: text.headlineSmall?.copyWith(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s2),
                    BigButton(
                      label: l.nextMakeBill,
                      icon: Icons.receipt_long_outlined,
                      busy: _busy,
                      onPressed: _lines.isEmpty ? null : () => _next(job),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.item,
    required this.line,
    required this.lang,
    required this.onAdd,
    required this.onRemove,
  });
  final CatalogItem item;
  final JobItem? line;
  final String lang;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final picked = line != null;
    return Material(
      color: picked ? Tokens.primary.withValues(alpha: 0.12) : scheme.surface,
      borderRadius: BorderRadius.circular(Tokens.radius),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(Tokens.radius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            Tokens.s3,
            Tokens.s2,
            Tokens.s2,
            Tokens.s2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(
              color: picked ? Tokens.primary : scheme.outlineVariant,
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Text(
                    item.name(lang),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rs ${Money.format(item.salePricePaisa)}/${unitLabel(l, item.unit)}',
                      style: text.bodySmall?.copyWith(
                        fontFamily: 'Roboto',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (picked) ...[
                    _RoundIcon(icon: Icons.remove, onTap: onRemove),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        formatQty(line!.qty),
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w800,
                          color: Tokens.primary,
                        ),
                      ),
                    ),
                  ],
                  _RoundIcon(icon: Icons.add, onTap: onAdd, filled: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 22,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? Tokens.primary : Colors.transparent,
        border: filled ? null : Border.all(color: Tokens.primary, width: 1.5),
      ),
      child: Icon(
        icon,
        size: 20,
        color: filled ? Colors.white : Tokens.primary,
      ),
    ),
  );
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.canEditPrice,
    required this.onMinus,
    required this.onPlus,
    required this.onQty,
    required this.onPrice,
    required this.onRemove,
  });
  final JobItem line;
  final bool canEditPrice;
  final VoidCallback onMinus, onPlus, onQty, onPrice, onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Tokens.s2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.s3,
          Tokens.s2,
          Tokens.s1,
          Tokens.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.description,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Rs ${Money.format(line.amountPaisa)}',
                  style: text.titleMedium?.copyWith(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  tooltip: l.remove,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: onRemove,
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundIcon(icon: Icons.remove, onTap: onMinus),
                    TextButton(
                      onPressed: onQty,
                      child: Text(
                        '${formatQty(line.qty)}${line.unit == null ? '' : ' ${unitLabel(l, line.unit!)}'}',
                        style: text.titleMedium?.copyWith(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _RoundIcon(icon: Icons.add, onTap: onPlus, filled: true),
                  ],
                ),
                TextButton.icon(
                  onPressed: canEditPrice ? onPrice : null,
                  icon: Icon(
                    canEditPrice ? Icons.edit_outlined : Icons.lock_outline,
                    size: 18,
                  ),
                  label: Text(
                    '× Rs ${Money.format(line.unitPricePaisa)}',
                    style: const TextStyle(fontFamily: 'Roboto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
