import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../data/local_store.dart';
import '../models/models.dart';
import '../services/currency_service.dart';
import '../utils/tx_image_helper.dart';

Future<void> showTxEditorSheet(
  BuildContext context, {
  required LocalStore store,
  Transaction? existing,
  DateTime? defaultDay,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => TxEditorSheet(
      store: store,
      existing: existing,
      defaultDay: defaultDay,
    ),
  );
}

class TxEditorSheet extends StatefulWidget {
  final LocalStore store;
  final Transaction? existing;
  final DateTime? defaultDay;

  const TxEditorSheet({
    super.key,
    required this.store,
    this.existing,
    this.defaultDay,
  });

  @override
  State<TxEditorSheet> createState() => _TxEditorSheetState();
}

class _TxEditorSheetState extends State<TxEditorSheet> {
  late String _type;
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _amount;
  late String _account;
  late String _toAccount;
  late String _category;
  late String _member;
  late DateTime _day;
  late String _subCategory;
  late List<String> _images;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final accounts = widget.store.accounts;
    _type = e?.type ?? 'Expense';
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.desc ?? '');
    _amount = TextEditingController(
        text: e == null ? '' : e.amount.toStringAsFixed(e.amount % 1 == 0 ? 0 : 2));
    _account = e?.account ??
        (accounts.isNotEmpty ? accounts.first.name : 'Cash');
    _toAccount = e?.toAccount ??
        (accounts.length > 1
            ? accounts[1].name
            : (accounts.isNotEmpty ? accounts.first.name : 'Bank'));
    _category = e?.category ??
        (widget.store.categories.isNotEmpty
            ? widget.store.categories.first.name
            : 'General');
    _member = e?.memberName ?? '';
    _subCategory = e?.subCategory ?? '';
    _images = List<String>.from(e?.images ?? const []);
    if (e != null && e.dayKey.length >= 10) {
      _day = DateTime.tryParse(e.dayKey) ?? DateTime.now();
    } else {
      _day = widget.defaultDay ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _addPhoto({required bool fromCamera}) async {
    if (_images.length >= TxImageHelper.maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 photos')),
      );
      return;
    }
    // Do NOT setState before opening the picker — browsers only allow the
    // file/camera dialog during the original tap gesture.
    try {
      final dataUrl =
          await TxImageHelper.pickOne(fromCamera: fromCamera);
      if (!mounted) return;
      if (dataUrl == null) return;
      setState(() => _images.add(dataUrl));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _previewPhoto(String dataUrl) {
    final provider = TxImageHelper.provider(dataUrl);
    if (provider == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image(image: provider, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    if (_type == 'Transfer' && _account == _toAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose different accounts for transfer')),
      );
      return;
    }
    final title = _title.text.trim().isEmpty
        ? (_type == 'Transfer' ? 'Transfer' : _type)
        : _title.text.trim();
    final dateStr =
        '${LocalStore.dayKey(_day)} ${DateFormat('HH:mm').format(DateTime.now())}';
    final isNew = widget.existing == null;
    final tx = Transaction(
      id: widget.existing?.id ?? LocalStore.newId(),
      title: title,
      desc: _desc.text.trim(),
      amount: amt,
      type: _type,
      account: _account,
      toAccount: _type == 'Transfer' ? _toAccount : '',
      category: _category,
      subCategory: _subCategory,
      date: dateStr,
      memberName: _member.trim(),
      images: _images.take(TxImageHelper.maxPhotos).toList(),
    );
    if (_member.trim().isNotEmpty) {
      await widget.store.addMember(_member.trim());
    }
    await widget.store.upsertTransaction(tx, isNew: isNew);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final accounts = widget.store.accounts.map((a) => a.name).toList();
    final cats = widget.store.categories.map((c) => c.name).toList();
    final members = ['', ...widget.store.members];

    if (accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Add an account in Settings first.'),
      );
    }

    final account = accounts.contains(_account) ? _account : accounts.first;
    final toAccount = accounts.contains(_toAccount)
        ? _toAccount
        : (accounts.length > 1 ? accounts[1] : accounts.first);
    final category =
        cats.isEmpty ? '' : (cats.contains(_category) ? _category : cats.first);
    final member = members.contains(_member) ? _member : '';
    final catObj = widget.store.categories
        .where((c) => c.name == category)
        .firstOrNull;
    final subs = catObj?.subCategories ?? const <String>[];
    final sub = subs.contains(_subCategory)
        ? _subCategory
        : (subs.isNotEmpty ? '' : '');
    final money = CurrencyService.instance;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.existing == null ? 'New transaction' : 'Edit transaction',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Expense', label: Text('Expense'), icon: Icon(Icons.remove_circle_outline, size: 16)),
                ButtonSegment(value: 'Income', label: Text('Income'), icon: Icon(Icons.add_circle_outline, size: 16)),
                ButtonSegment(value: 'Transfer', label: Text('Transfer'), icon: Icon(Icons.swap_horiz, size: 16)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              decoration: InputDecoration(
                labelText: money.amountLabel(),
                prefixText: '${money.current.symbol} ',
              ),
              autofocus: widget.existing == null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'What was this for?',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
              ),
            ),
            const SizedBox(height: 12),
            if (_type == 'Transfer') ...[
              DropdownButtonFormField<String>(
                key: ValueKey('from_$account'),
                initialValue: account,
                items: accounts
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _account = v ?? _account),
                decoration: const InputDecoration(labelText: 'From account'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('to_$toAccount'),
                initialValue: toAccount,
                items: accounts
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _toAccount = v ?? _toAccount),
                decoration: const InputDecoration(labelText: 'To account'),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('acc_$account'),
                initialValue: account,
                items: accounts
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _account = v ?? _account),
                decoration: const InputDecoration(labelText: 'Account'),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('cat_$category'),
              initialValue: category.isEmpty ? null : category,
              items: cats
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() {
                _category = v ?? _category;
                _subCategory = '';
              }),
              decoration: InputDecoration(
                labelText: _type == 'Transfer'
                    ? 'Category (optional)'
                    : 'Category',
              ),
            ),
            if (subs.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('sub_${category}_$sub'),
                initialValue: sub.isEmpty ? '' : sub,
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('No sub-category')),
                  ...subs.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (v) => setState(() => _subCategory = v ?? ''),
                decoration: const InputDecoration(labelText: 'Sub-category'),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('mem_$member'),
              initialValue: member,
              items: members
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.isEmpty ? 'No member tag' : m),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _member = v ?? ''),
              decoration: const InputDecoration(labelText: 'Family member (optional)'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final c = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Add member'),
                    content: TextField(
                      controller: c,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Name'),
                      onSubmitted: (v) => Navigator.pop(ctx, v),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, c.text),
                          child: const Text('Add')),
                    ],
                  ),
                );
                if (name != null && name.trim().isNotEmpty) {
                  await widget.store.addMember(name.trim());
                  setState(() => _member = name.trim());
                }
              },
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('New member'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined, color: AppTheme.primary),
              title: Text(DateFormat('EEE, d MMM yyyy').format(_day)),
              subtitle: const Text('Transaction date'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Photos',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${_images.length}/${TxImageHelper.maxPhotos}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_images.isNotEmpty)
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final provider = TxImageHelper.provider(_images[i]);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          onTap: () => _previewPhoto(_images[i]),
                          borderRadius: BorderRadius.circular(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: provider == null
                                ? Container(
                                    width: 78,
                                    height: 78,
                                    color: const Color(0xFFE2E8F0),
                                    child: const Icon(Icons.broken_image),
                                  )
                                : Image(
                                    image: provider,
                                    width: 78,
                                    height: 78,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.expense,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(4),
                              minimumSize: const Size(28, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: () =>
                                setState(() => _images.removeAt(i)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _images.length >= TxImageHelper.maxPhotos
                        ? null
                        : () => _addPhoto(fromCamera: true),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _images.length >= TxImageHelper.maxPhotos
                        ? null
                        : () => _addPhoto(fromCamera: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _save,
              child: Text(widget.existing == null ? 'Save' : 'Update'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppTheme.expense),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete transaction?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await widget.store.deleteTransaction(widget.existing!.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
