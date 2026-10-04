import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';

class WorkflowField extends StatelessWidget {
  const WorkflowField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });
  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Search a named choice, without displaying database identifiers to the user.
class WorkflowSelect extends StatefulWidget {
  const WorkflowSelect({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.placeholder = 'Choose an option',
    this.enabled = true,
    this.searchable = true,
  });
  final String label;
  final Map<String, String> options;
  final String? value;
  final String placeholder;
  final bool enabled, searchable;
  final ValueChanged<String> onChanged;

  @override
  State<WorkflowSelect> createState() => _WorkflowSelectState();
}

class _WorkflowSelectState extends State<WorkflowSelect> {
  String _search = '';

  @override
  Widget build(BuildContext context) => WorkflowField(
    label: widget.label,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final options = widget.options.entries
            .where((option) => option.value.toLowerCase().contains(_search))
            .map(
              (option) => ShadOption<String>(
                value: option.key,
                child: Text(
                  option.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList();
        final width = constraints.maxWidth;
        final key = ValueKey('${widget.label}-${widget.value}');
        Widget selected(BuildContext context, String value) => Text(
          widget.options[value] ?? value,
          overflow: TextOverflow.ellipsis,
        );
        void changed(String? value) {
          if (value != null && widget.options.containsKey(value)) {
            widget.onChanged(value);
          }
        }

        return widget.searchable
            ? ShadSelect<String>.withSearch(
                key: key,
                initialValue: widget.value,
                enabled: widget.enabled,
                minWidth: width,
                maxWidth: width,
                maxHeight: 260,
                placeholder: Text(widget.placeholder),
                searchPlaceholder: const Text('Search by name…'),
                clearSearchOnClose: true,
                onSearchChanged: (value) =>
                    setState(() => _search = value.toLowerCase()),
                options: options,
                selectedOptionBuilder: selected,
                onChanged: changed,
              )
            : ShadSelect<String>(
                key: key,
                initialValue: widget.value,
                enabled: widget.enabled,
                minWidth: width,
                maxWidth: width,
                placeholder: Text(widget.placeholder),
                options: options,
                selectedOptionBuilder: selected,
                onChanged: changed,
              );
      },
    ),
  );
}

class WorkflowNotice extends StatelessWidget {
  const WorkflowNotice({
    super.key,
    required this.title,
    required this.message,
    this.error = false,
  });
  final String title, message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: error
        ? ShadAlert.destructive(
            icon: const Icon(LucideIcons.circleAlert, size: 17),
            title: Text(title),
            description: Text(message),
          )
        : ShadAlert(
            icon: const Icon(LucideIcons.info, size: 17),
            title: Text(title),
            description: Text(message),
          ),
  );
}

class WorkflowComparison extends StatelessWidget {
  const WorkflowComparison({
    super.key,
    required this.label,
    required this.before,
    required this.after,
  });
  final String label, before, after;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(before),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Icon(
                LucideIcons.arrowRight,
                size: 16,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'After saving',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    after,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
