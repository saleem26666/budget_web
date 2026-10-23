import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../app_theme.dart';
import '../data/local_store.dart';
import '../models/models.dart';
import '../services/currency_service.dart';
import '../utils/tx_image_helper.dart';
import '../widgets/balance_card.dart';
import '../widgets/tx_editor_sheet.dart';
import 'reports_screen.dart';
import 'settings_backup_screen.dart';

class WalletScreen extends StatefulWidget {
  final LocalStore store;

  const WalletScreen({super.key, required this.store});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  String _query = '';
  String? _memberFilter;
  bool _weekExpanded = false;

  LocalStore get store => widget.store;

  Future<void> _pickProfile() async {
    if (store.profiles.isEmpty) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Switch profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in store.profiles)
                    ListTile(
                      selected: p.id == store.activeProfileId,
                      leading: Text(
                        p.id == store.activeProfileId ? '✓' : '○',
                        style: TextStyle(
                          fontSize: 20,
                          color: p.id == store.activeProfileId
                              ? AppTheme.primary
                              : AppTheme.muted,
                        ),
                      ),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${p.accounts.length} accounts · ${p.transactions.length} txs',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      onTap: () => Navigator.pop(ctx, p.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (id != null) {
      await store.switchProfile(id);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = store.snapshotForDay(_selected);
    final list = store.filteredForDay(
      day: _selected,
      memberFilter: _memberFilter,
      query: _query,
    );
    final money = CurrencyService.instance;
    final width = MediaQuery.sizeOf(context).width;
    final maxW = width > 720 ? 720.0 : width;

    return ListenableBuilder(
      listenable: Listenable.merge([money, store]),
      builder: (context, _) {
        return Scaffold(
      appBar: AppBar(
        title: TextButton(
          onPressed: _pickProfile,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(
            store.profiles.length > 1
                ? '${store.activeProfileName} ▼'
                : 'Budget Web',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Switch profile',
            icon: const Icon(Icons.people),
            onPressed: _pickProfile,
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final c = TextEditingController(text: _query);
              final q = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Search transactions'),
                  content: TextField(
                    controller: c,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Title, note, account, member…',
                    ),
                    onSubmitted: (v) => Navigator.pop(ctx, v),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: const Text('Clear'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('Search'),
                    ),
                  ],
                ),
              );
              if (q != null) setState(() => _query = q.trim());
            },
          ),
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.assessment_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReportsScreen(store: store),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsBackupScreen(store: store),
                  ),
                );
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Settings'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTxEditorSheet(
          context,
          store: store,
          defaultDay: _selected,
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              BalanceCard(
                snap: snap,
                selectedDay: _selected,
                onTapDate: () => setState(() => _weekExpanded = !_weekExpanded),
              ),
              const SizedBox(height: 14),
              _accountPills(snap, money),
              const SizedBox(height: 8),
              if (store.members.isNotEmpty) _memberChips(),
              if (_query.isNotEmpty) ...[
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(Icons.search, size: 16),
                  label: Text('“$_query”'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _query = ''),
                ),
              ],
              const SizedBox(height: 8),
              _calendarStrip(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    _query.isEmpty
                        ? DateFormat('EEEE, d MMM').format(_selected)
                        : 'Search results',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${list.length}',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                _emptyDay()
              else
                ...list.map((t) => _txTile(t, money)),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _accountPills(WalletSnapshot snap, CurrencyService money) {
    // Same as Android: every balance key (incl. transfer targets), not only
    // named wallet accounts — missing chips hid ~balance gaps before.
    final names = snap.accounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (names.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: names.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final name = names[i];
          final bal = snap.accounts[name] ?? 0;
          return InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _showAccountDetail(name, snap),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: AppTheme.listTile(radius: 22),
              child: Row(
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money.format(bal),
                    style: TextStyle(
                      color: bal >= 0 ? AppTheme.primary : AppTheme.expense,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAccountDetail(String name, WalletSnapshot snap) async {
    final rows = store.statementRows(name);
    final meta = rows.firstWhere((r) => r['_meta'] == true, orElse: () => {});
    final money = CurrencyService.instance;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ListView(
            controller: scroll,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'As of ${DateFormat('d MMM yyyy').format(_selected)}: ${money.format(snap.accounts[name] ?? 0)}',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metaChip('Opening', money.format(meta['opening'] ?? 0)),
                  _metaChip('In', money.format(meta['totalIn'] ?? 0)),
                  _metaChip('Out', money.format(meta['totalOut'] ?? 0)),
                  _metaChip('Closing', money.format(meta['closing'] ?? 0)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Recent',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...rows.where((r) => r['_meta'] != true).take(20).map((r) {
                final signed = (r['signed'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text((r['title'] ?? '').toString()),
                  subtitle: Text('${r['date']} · ${r['type']}'),
                  trailing: Text(
                    money.format(signed.abs()),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: signed >= 0 ? AppTheme.income : AppTheme.expense,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: AppTheme.listTile(radius: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _memberChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: _memberFilter == null,
              onSelected: (_) => setState(() => _memberFilter = null),
            ),
          ),
          ...store.members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(m),
                selected: _memberFilter == m,
                onSelected: (_) => setState(
                    () => _memberFilter = _memberFilter == m ? null : m),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarStrip() {
    return Container(
      decoration: AppTheme.listTile(radius: 16),
      padding: const EdgeInsets.only(bottom: 8),
      child: TableCalendar(
        firstDay: DateTime(2000),
        lastDay: DateTime(2100),
        focusedDay: _focused,
        selectedDayPredicate: (d) => isSameDay(d, _selected),
        calendarFormat:
            _weekExpanded ? CalendarFormat.month : CalendarFormat.week,
        availableCalendarFormats: const {
          CalendarFormat.week: 'Week',
          CalendarFormat.month: 'Month',
        },
        onFormatChanged: (f) =>
            setState(() => _weekExpanded = f == CalendarFormat.month),
        headerStyle: const HeaderStyle(
          formatButtonVisible: true,
          titleCentered: false,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          leftChevronIcon: Icon(Icons.chevron_left, size: 22),
          rightChevronIcon: Icon(Icons.chevron_right, size: 22),
        ),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: AppTheme.primaryDark,
            fontWeight: FontWeight.w700,
          ),
          selectedDecoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          outsideDaysVisible: false,
        ),
        onDaySelected: (sel, foc) {
          setState(() {
            _selected = sel;
            _focused = foc;
            if (_query.isNotEmpty) _query = '';
          });
        },
        onPageChanged: (f) => _focused = f,
      ),
    );
  }

  Widget _emptyDay() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(28),
      decoration: AppTheme.listTile(radius: 18),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 42, color: AppTheme.muted.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            _query.isEmpty
                ? 'No transactions this day'
                : 'No matches for “$_query”',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap Add to record income, expense, or transfer.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => showTxEditorSheet(
              context,
              store: store,
              defaultDay: _selected,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    );
  }

  Widget _txTile(Transaction t, CurrencyService money) {
    Color accent;
    IconData icon;
    String amountLabel;
    switch (t.type) {
      case 'Income':
        accent = AppTheme.income;
        icon = Icons.south_west_rounded;
        amountLabel = '+${money.format(t.amount)}';
        break;
      case 'Transfer':
        accent = AppTheme.transfer;
        icon = Icons.swap_horiz_rounded;
        amountLabel = money.format(t.amount);
        break;
      default:
        accent = AppTheme.expense;
        icon = Icons.north_east_rounded;
        amountLabel = '-${money.format(t.amount)}';
    }
    final subtitle = t.type == 'Transfer'
        ? '${t.account} → ${t.toAccount}'
        : [
            t.account,
            if (t.category.isNotEmpty) t.category,
            if (t.memberName.isNotEmpty) t.memberName,
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showTxEditorSheet(context, store: store, existing: t),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: AppTheme.listTile(),
            child: Row(
              children: [
                Builder(
                  builder: (_) {
                    final thumb = t.images.isNotEmpty
                        ? TxImageHelper.provider(t.images.first)
                        : null;
                    if (thumb != null) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image(
                          image: thumb,
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                        ),
                      );
                    }
                    return Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title.isEmpty ? t.type : t.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          subtitle,
                          if (t.images.isNotEmpty)
                            '${t.images.length} photo${t.images.length == 1 ? '' : 's'}',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  amountLabel,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
