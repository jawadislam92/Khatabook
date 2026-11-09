import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/big_button.dart';
import '../../l10n/app_localizations.dart';
import 'invoice_models.dart';
import 'invoices_repository.dart';

/// What prints at the top and bottom of every bill.
class BusinessProfileScreen extends ConsumerStatefulWidget {
  const BusinessProfileScreen({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<BusinessProfileScreen> createState() =>
      _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends ConsumerState<BusinessProfileScreen> {
  final _c = <String, TextEditingController>{};
  bool _loaded = false;
  bool _busy = false;
  bool _tax = false;

  static const _fields = [
    'nameEn',
    'nameUr',
    'tagline',
    'phone',
    'email',
    'address',
    'bankName',
    'accountTitle',
    'accountNumber',
    'easypaisa',
    'jazzcash',
    'invoicePrefix',
    'termsText',
    'taxRate',
  ];

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      _c[f] = TextEditingController();
    }
    ref.read(invoicesRepositoryProvider).businessProfile(widget.spaceId).then((
      p,
    ) {
      if (!mounted) return;
      final bp = p ?? BusinessProfile(spaceId: widget.spaceId);
      _c['nameEn']!.text = bp.nameEn;
      _c['nameUr']!.text = bp.nameUr ?? '';
      _c['tagline']!.text = bp.tagline ?? '';
      _c['phone']!.text = bp.phone ?? '';
      _c['email']!.text = bp.email ?? '';
      _c['address']!.text = bp.address ?? '';
      _c['bankName']!.text = bp.bankName ?? '';
      _c['accountTitle']!.text = bp.accountTitle ?? '';
      _c['accountNumber']!.text = bp.accountNumber ?? '';
      _c['easypaisa']!.text = bp.easypaisa ?? '';
      _c['jazzcash']!.text = bp.jazzcash ?? '';
      _c['invoicePrefix']!.text = bp.invoicePrefix;
      _c['termsText']!.text = bp.termsText ?? '';
      _c['taxRate']!.text = bp.taxRateBp == 0
          ? ''
          : (bp.taxRateBp / 100).toString();
      setState(() {
        _tax = bp.taxEnabled;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_c['nameEn']!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.errorNameRequired)));
      return;
    }
    setState(() => _busy = true);
    final rate = double.tryParse(_c['taxRate']!.text.trim()) ?? 0;
    try {
      await ref
          .read(invoicesRepositoryProvider)
          .saveBusinessProfile(
            BusinessProfile(
              spaceId: widget.spaceId,
              nameEn: _c['nameEn']!.text.trim(),
              nameUr: _c['nameUr']!.text,
              tagline: _c['tagline']!.text,
              phone: _c['phone']!.text,
              email: _c['email']!.text,
              address: _c['address']!.text,
              bankName: _c['bankName']!.text,
              accountTitle: _c['accountTitle']!.text,
              accountNumber: _c['accountNumber']!.text,
              easypaisa: _c['easypaisa']!.text,
              jazzcash: _c['jazzcash']!.text,
              termsText: _c['termsText']!.text,
              taxEnabled: _tax,
              taxRateBp: (rate * 100).round().clamp(0, 10000),
              invoicePrefix: _c['invoicePrefix']!.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.saved)));
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget field(
      String key,
      String label, {
      String? hint,
      TextInputType? type,
      int lines = 1,
      TextDirection? direction,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Tokens.s3),
      child: TextField(
        controller: _c[key],
        keyboardType: type,
        maxLines: lines,
        textDirection: direction,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
    Widget heading(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(0, Tokens.s3, 0, Tokens.s2),
      child: Text(
        s,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.businessDetails)),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.s4,
                0,
                Tokens.s4,
                Tokens.s7 * 2,
              ),
              children: [
                field('nameEn', l.businessNameEn),
                field('nameUr', l.businessNameUr, direction: TextDirection.rtl),
                field('tagline', l.tagline),
                field('phone', l.phone, type: TextInputType.phone),
                field('email', l.email, type: TextInputType.emailAddress),
                field('address', l.address, lines: 2),
                heading(l.pdfPayTo),
                field('bankName', l.bankName),
                field('accountTitle', l.accountTitle),
                field('accountNumber', l.accountNumber),
                field(
                  'easypaisa',
                  l.easypaisaNumber,
                  type: TextInputType.phone,
                ),
                field('jazzcash', l.jazzcashNumber, type: TextInputType.phone),
                heading(l.tabInvoices),
                field('invoicePrefix', l.invoicePrefix),
                field(
                  'termsText',
                  l.invoiceTerms,
                  hint: l.invoiceTermsHint,
                  lines: 3,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.taxEnabled),
                  value: _tax,
                  onChanged: (v) => setState(() => _tax = v),
                ),
                if (_tax)
                  field(
                    'taxRate',
                    l.taxRate,
                    type: const TextInputType.numberWithOptions(decimal: true),
                  ),
                const SizedBox(height: Tokens.s4),
                BigButton(
                  label: l.save,
                  icon: Icons.check,
                  busy: _busy,
                  onPressed: _save,
                ),
              ],
            ),
    );
  }
}
