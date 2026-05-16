import 'package:flutter/material.dart';
import 'icon_catalog.dart';

/// Shows a searchable icon-picker bottom sheet.
/// Returns the selected icon [name] string (stored in Goal.emoji), or null
/// if the user dismissed without picking.
Future<String?> showEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _IconPickerSheet(),
  );
}

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet();

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet> {
  String _query = '';

  List<IconEntry> get _filtered {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return [
      for (final cat in iconCatalog)
        for (final e in cat.entries)
          if (e.label.toLowerCase().contains(q) ||
              e.name.toLowerCase().contains(q))
            e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSearching = _query.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search icons…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _query = ''),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // Icon grid
            Expanded(
              child: isSearching
                  ? _SearchResults(
                      entries: _filtered,
                      scrollCtrl: scrollCtrl,
                      onSelect: (name) => Navigator.pop(context, name),
                    )
                  : _CategoryBrowse(
                      scrollCtrl: scrollCtrl,
                      onSelect: (name) => Navigator.pop(context, name),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Browse mode — shows all categories with section headers
// ---------------------------------------------------------------------------

class _CategoryBrowse extends StatelessWidget {
  final ScrollController scrollCtrl;
  final ValueChanged<String> onSelect;

  const _CategoryBrowse({
    required this.scrollCtrl,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollCtrl,
      slivers: [
        for (final cat in iconCatalog) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                cat.title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: cat.entries.length,
              itemBuilder: (_, i) => _IconCell(
                entry: cat.entries[i],
                onTap: () => onSelect(cat.entries[i].name),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search results — flat grid
// ---------------------------------------------------------------------------

class _SearchResults extends StatelessWidget {
  final List<IconEntry> entries;
  final ScrollController scrollCtrl;
  final ValueChanged<String> onSelect;

  const _SearchResults({
    required this.entries,
    required this.scrollCtrl,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No icons found',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) => _IconCell(
        entry: entries[i],
        onTap: () => onSelect(entries[i].name),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single icon cell
// ---------------------------------------------------------------------------

class _IconCell extends StatelessWidget {
  final IconEntry entry;
  final VoidCallback onTap;

  const _IconCell({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: entry.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entry.icon, size: 26, color: cs.onSurface),
          ],
        ),
      ),
    );
  }
}
