/// ColiseuSearch — Barra de busca premium com filtro tipado e debounce.
///
/// Genérica: aceita qualquer enum/tipo como filtro via dropdown.
/// Trailing: ícone de limpar + ícone custom (ex: scanner).
/// Debounce integrado (300ms).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../core/design/app_colors.dart';
import '../core/design/app_typography.dart';

/// Par label+valor para o dropdown de filtro.
class SearchFilter<T> {
  final String label;
  final T value;
  const SearchFilter({required this.label, required this.value});
}

class ColiseuSearch<T> extends StatefulWidget {
  final String hint;
  final List<SearchFilter<T>> filters;
  final T? selectedFilter;
  final ValueChanged<T?> onFilterChanged;
  final ValueChanged<String> onSearch;
  final Widget? trailingAction;
  final Duration debounceDuration;

  const ColiseuSearch({
    super.key,
    this.hint = 'Buscar...',
    this.filters = const [],
    this.selectedFilter,
    required this.onFilterChanged,
    required this.onSearch,
    this.trailingAction,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  @override
  State<ColiseuSearch<T>> createState() => _ColiseuSearchState<T>();
}

class _ColiseuSearchState<T> extends State<ColiseuSearch<T>> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      widget.onSearch(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.surfacePrimary,
      child: Row(
        children: [
          if (widget.filters.isNotEmpty)
            _buildFilterChip(),
          if (widget.filters.isNotEmpty)
            const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _ctrl.clear();
                          widget.onSearch('');
                        },
                      )
                    : widget.trailingAction,
                isDense: true,
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip() {
    final selected = widget.filters.where((f) => f.value == widget.selectedFilter).firstOrNull;
    final label = selected?.label ?? 'Todos';

    return Material(
      color: widget.selectedFilter != null
          ? AppColors.primary.withOpacity(0.1)
          : AppColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_rounded, size: 16,
                color: widget.selectedFilter != null ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: widget.selectedFilter != null ? AppColors.primary : AppColors.textSecondary)),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 16,
                color: widget.selectedFilter != null ? AppColors.primary : AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.filter_list_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text('Filtrar por...', style: AppTypography.headingSmall),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                widget.selectedFilter == null ? Icons.radio_button_checked : Icons.radio_button_off,
                color: widget.selectedFilter == null ? AppColors.primary : AppColors.textTertiary, size: 20),
              title: const Text('Todos'),
              onTap: () { Navigator.pop(ctx); widget.onFilterChanged(null); },
            ),
            ...widget.filters.map((f) => ListTile(
              leading: Icon(
                f.value == widget.selectedFilter ? Icons.radio_button_checked : Icons.radio_button_off,
                color: f.value == widget.selectedFilter ? AppColors.primary : AppColors.textTertiary, size: 20),
              title: Text(f.label),
              onTap: () { Navigator.pop(ctx); widget.onFilterChanged(f.value); },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
