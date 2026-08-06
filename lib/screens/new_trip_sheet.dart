import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/person.dart';
import '../models/trip.dart';
import '../state/app_state.dart';

/// Creates or edits a trip — the container every entry has to belong to.
///
/// Opens as a bottom sheet so it works the same on phone and desktop.
class NewTripSheet extends StatefulWidget {
  /// When set, the sheet edits this trip instead of creating a new one.
  final Trip? initial;

  const NewTripSheet({super.key, this.initial});

  /// Returns true when a trip was created or edited.
  static Future<bool> show(BuildContext context, {Trip? initial}) async {
    // The sheet is a route on the app's Navigator, which makes it a *sibling*
    // of the provider rather than a descendant — it cannot look AppState up on
    // its own. Hand the existing instance across the boundary explicitly.
    final appState = context.read<AppState>();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: appState,
        child: NewTripSheet(initial: initial),
      ),
    );
    return saved ?? false;
  }

  @override
  State<NewTripSheet> createState() => _NewTripSheetState();
}

class _NewTripSheetState extends State<NewTripSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();

  DateTime _start = DateTime.now();
  DateTime? _end = DateTime.now();
  bool _ongoing = false;
  final Set<String> _companionIds = {};

  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    if (t != null) {
      _title.text = t.title;
      _start = t.startDate;
      _end = t.endDate;
      _ongoing = t.endDate == null;
      _companionIds.addAll(t.companions.map((p) => p.id));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// One calendar for both ends: tap the start, then the end (which the picker
  /// forces to be on or after the start), and it fills the span between.
  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end ?? _start),
      helpText: '选择旅途日期',
      saveText: '完成',
    );
    if (range == null) return;
    setState(() {
      _start = range.start;
      _end = range.end;
    });
  }

  /// For an ongoing trip there is no end, so only the start is picked.
  Future<void> _pickStartOnly() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final appState = context.read<AppState>();
    final companions = [
      for (final p in appState.people)
        if (_companionIds.contains(p.id)) p,
    ];

    try {
      await appState.addTrip(Trip(
        // Keep the id when editing; a new client-generated one otherwise, so a
        // trip has an identity even if it was created with no connection.
        id: widget.initial?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        startDate: _start,
        endDate: _ongoing ? null : _end,
        companions: companions,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();
    final fmt = DateFormat('yyyy年M月d日');

    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        // Scrollable, so the sheet survives short viewports (landscape phones,
        // keyboard up) instead of overflowing.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_editing ? '编辑旅途' : '新建旅途',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _title,
                  autofocus: !_editing,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: '旅途名称',
                    hintText: '例如：京都之旅',
                    prefixIcon: Icon(Icons.luggage_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? '给这趟旅途起个名字' : null,
                ),
                const SizedBox(height: 14),

                _DateField(
                  label: '日期',
                  text: _ongoing
                      ? '${fmt.format(_start)} 起 · 进行中'
                      : '${fmt.format(_start)} – ${fmt.format(_end ?? _start)}',
                  onTap: _ongoing ? _pickStartOnly : _pickRange,
                ),
                CheckboxListTile(
                  value: _ongoing,
                  onChanged: (v) => setState(() => _ongoing = v ?? false),
                  title: const Text('还在进行中（无结束日期）'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 6),

                // ---- companions: who this trip is with ----
                Row(
                  children: [
                    Text('同行人', style: theme.textTheme.labelLarge),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : _addPerson,
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (appState.people.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('还没有同行人，点“添加”新建',
                        style:
                            TextStyle(color: theme.hintColor, fontSize: 13)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in appState.people)
                        FilterChip(
                          label: Text(p.name),
                          selected: _companionIds.contains(p.id),
                          onSelected: (on) => setState(() {
                            on
                                ? _companionIds.add(p.id)
                                : _companionIds.remove(p.id);
                          }),
                        ),
                    ],
                  ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_editing ? '保存' : '创建'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addPerson() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加同行人'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '姓名'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final person = Person(id: const Uuid().v4(), name: name);
    try {
      await context.read<AppState>().addPerson(person);
      if (mounted) setState(() => _companionIds.add(person.id));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String text;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
