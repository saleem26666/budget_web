import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../data/local_store.dart';
import '../services/backup_share.dart';
import '../services/currency_service.dart';
import '../services/report_pdf_service.dart';
import '../utils/tx_image_helper.dart';

class ReportsScreen extends StatefulWidget {
  final LocalStore store;

  const ReportsScreen({super.key, required this.store});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _all = 'All accounts';

  late String _account;
  late DateTime _from;
  late DateTime _to;
  bool _busy = false;

  LocalStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _account =
        store.accounts.isNotEmpty ? store.accounts.first.name : _all;
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _pickAccount(
    List<String> accounts,
    String Function(String) balLabel,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.65;
        return SizedBox(
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Select account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (_, i) {
                    final a = accounts[i];
                    final selected = a == _account;
                    return ListTile(
                      selected: selected,
                      title: Text(
                        a,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      trailing: Text(
                        balLabel(a),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, a),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => _account = picked);
  }

  Map<String, dynamic>? get _singleReport {
    if (_account == _all) return null;
    return store.reportForAccount(
      accountName: _account,
      from: _from,
      to: _to,
    );
  }

  List<Map<String, dynamic>> get _allReports => store.reportAllAccounts(
        from: _from,
        to: _to,
      );

  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      if (_account == _all) {
        final bytes = await ReportPdfService.buildAllAccountsPdf(_allReports);
        await BackupShare.downloadBytes(
          bytes,
          fileName: 'BudgetWeb_AllAccounts_$stamp.pdf',
          mime: 'application/pdf',
        );
      } else {
        final report = _singleReport!;
        final bytes = await ReportPdfService.buildAccountPdf(report);
        final safe = _account.replaceAll(RegExp(r'[^\w\-]+'), '_');
        await BackupShare.downloadBytes(
          bytes,
          fileName: 'BudgetWeb_${safe}_$stamp.pdf',
          mime: 'application/pdf',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF downloaded')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = CurrencyService.instance;
    final snap = store.snapshotForDay(DateTime.now());
    final accountNames = store.accounts.map((a) => a.name).toList();
    final accounts = [_all, ...accountNames];
    if (!accounts.contains(_account)) {
      _account = accounts.first;
    }
    final df = DateFormat('d MMM yyyy');
    final single = _singleReport;
    final all = _account == _all ? _allReports : null;

    String balLabel(String name) {
      if (name == _all) return money.format(snap.balance);
      return money.format(snap.accounts[name] ?? 0);
    }

    return ListenableBuilder(
      listenable: money,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _downloadPdf,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.listTile(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: InkWell(
                        onTap: () => _pickAccount(accounts, balLabel),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _account,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                balLabel(_account),
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFrom,
                            icon: const Icon(Icons.event, size: 18),
                            label: Text('From ${df.format(_from)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickTo,
                            icon: const Icon(Icons.event, size: 18),
                            label: Text('To ${df.format(_to)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'History + PDF for selected account and dates. '
                      '“All accounts” = summary PDF.',
                      style: TextStyle(
                        color: AppTheme.muted.withValues(alpha: 0.95),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (all != null) ...[
                ...all.map((r) => _accountSummaryCard(r, money)),
              ] else if (single != null) ...[
                _summaryStrip(single, money),
                const SizedBox(height: 12),
                Text(
                  'Transactions (${(single['rows'] as List).length})',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if ((single['rows'] as List).isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.listTile(),
                    child: const Text(
                      'No transactions in this date range.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                else
                  ...(single['rows'] as List).cast<Map>().map((r) {
                    final signed =
                        (r['signed'] as num?)?.toDouble() ?? 0;
                    final run =
                        (r['running_balance'] as num?)?.toDouble() ?? 0;
                    final imgs = TxImageHelper.parseFromBackup(
                      Map<String, dynamic>.from(r),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: AppTheme.listTile(),
                        child: Row(
                          children: [
                            if (imgs.isNotEmpty) ...[
                              Builder(
                                builder: (_) {
                                  final p =
                                      TxImageHelper.provider(imgs.first);
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(right: 10),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: p == null
                                          ? const SizedBox(
                                              width: 40, height: 40)
                                          : Image(
                                              image: p,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (r['title'] ?? r['type'] ?? '')
                                        .toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r['date']} · ${r['type']}'
                                    '${(r['category'] ?? '').toString().isNotEmpty ? ' · ${r['category']}' : ''}'
                                    '${imgs.isNotEmpty ? ' · ${imgs.length} photo${imgs.length == 1 ? '' : 's'}' : ''}',
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  money.format(signed),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: signed >= 0
                                        ? AppTheme.income
                                        : AppTheme.expense,
                                  ),
                                ),
                                Text(
                                  'Bal ${money.format(run)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _summaryStrip(Map<String, dynamic> r, CurrencyService money) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.balanceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r['account']?.toString() ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill('Opening', money.format(r['opening'] ?? 0)),
              const SizedBox(width: 8),
              _pill('In', money.format(r['totalIn'] ?? 0)),
              const SizedBox(width: 8),
              _pill('Out', money.format(r['totalOut'] ?? 0)),
              const SizedBox(width: 8),
              _pill('Closing', money.format(r['closing'] ?? 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 10)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _accountSummaryCard(
      Map<String, dynamic> r, CurrencyService money) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _account = r['account'].toString()),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.listTile(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['account']?.toString() ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'Open ${money.format(r['opening'] ?? 0)} · '
                  'In ${money.format(r['totalIn'] ?? 0)} · '
                  'Out ${money.format(r['totalOut'] ?? 0)} · '
                  'Close ${money.format(r['closing'] ?? 0)}',
                  style: const TextStyle(
                      color: AppTheme.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(r['rows'] as List).length} txs · tap for detail',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
