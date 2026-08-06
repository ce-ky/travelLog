import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';
import '../models/person.dart';
import '../state/app_state.dart';
import '../widgets/entry_card.dart';

/// Browse the places you went with each companion, and edit companions
/// (add / rename / delete). Lives inside the Browse tab.
class CompanionsView extends StatefulWidget {
  const CompanionsView({super.key});

  @override
  State<CompanionsView> createState() => _CompanionsViewState();
}

class _CompanionsViewState extends State<CompanionsView> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final people = appState.people;

    // Keep the selection valid across edits/deletes.
    if (_selectedId != null && !people.any((p) => p.id == _selectedId)) {
      _selectedId = null;
    }

    if (people.isEmpty) {
      return _EmptyPeople(onAdd: () => _addPerson(context));
    }

    final selected = people.where((p) => p.id == _selectedId).firstOrNull;
    final List<Entry> entries = selected == null
        ? const <Entry>[]
        : appState.entriesWithPerson(selected.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // People as selectable chips + an add action.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in people)
                ChoiceChip(
                  avatar: CircleAvatar(
                    radius: 10,
                    child: Text(p.name.characters.first,
                        style: const TextStyle(fontSize: 11)),
                  ),
                  label: Text(p.name),
                  selected: _selectedId == p.id,
                  onSelected: (on) =>
                      setState(() => _selectedId = on ? p.id : null),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
                onPressed: () => _addPerson(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: selected == null
              ? const Center(
                  child: Text('选择一位同行人，查看一起去过的地方'))
              : _CompanionDetail(
                  person: selected,
                  entries: entries,
                  onRename: () => _renamePerson(context, selected),
                  onDelete: () => _deletePerson(context, selected),
                ),
        ),
      ],
    );
  }

  Future<void> _addPerson(BuildContext context) async {
    final appState = context.read<AppState>();
    final name = await _nameDialog(context, title: '添加同行人');
    if (name == null || name.isEmpty) return;
    final person = Person(id: const Uuid().v4(), name: name);
    await appState.addPerson(person);
    if (mounted) setState(() => _selectedId = person.id);
  }

  Future<void> _renamePerson(BuildContext context, Person person) async {
    final appState = context.read<AppState>();
    final name =
        await _nameDialog(context, title: '重命名', initial: person.name);
    if (name == null || name.isEmpty || name == person.name) return;
    await appState.addPerson(
        Person(id: person.id, name: name, avatarPath: person.avatarPath));
  }

  Future<void> _deletePerson(BuildContext context, Person person) async {
    final appState = context.read<AppState>();
    final tripCount = appState.tripsWithPerson(person.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除同行人'),
        content: Text(tripCount == 0
            ? '确定删除「${person.name}」吗？'
            : '「${person.name}」会从 $tripCount 趟旅途的同行人中移除，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await appState.removePerson(person.id);
  }

  Future<String?> _nameDialog(BuildContext context,
      {required String title, String? initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _CompanionDetail extends StatelessWidget {
  final Person person;
  final List<Entry> entries;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _CompanionDetail({
    required this.person,
    required this.entries,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('与 ${person.name} · ${entries.length} 处',
                    style: theme.textTheme.titleSmall),
              ),
              IconButton(
                icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                tooltip: '重命名',
                onPressed: onRename,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '删除',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('还没有和 TA 一起的记录'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => EntryCard(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyPeople({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 56, color: theme.hintColor),
            const SizedBox(height: 16),
            Text('还没有同行人', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('添加同行人后，可以按人筛选一起去过的地方。',
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('添加同行人'),
            ),
          ],
        ),
      ),
    );
  }
}
