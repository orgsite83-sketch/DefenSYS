import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditDateRangeDialog extends StatefulWidget {
  final String initialStartDate;
  final String initialEndDate;
  final Function(String startDate, String endDate) onApply;

  const AuditDateRangeDialog({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.onApply,
  });

  static void show(
    BuildContext context, {
    required String initialStartDate,
    required String initialEndDate,
    required Function(String startDate, String endDate) onApply,
  }) {
    showDialog(
      context: context,
      builder: (context) => AuditDateRangeDialog(
        initialStartDate: initialStartDate,
        initialEndDate: initialEndDate,
        onApply: onApply,
      ),
    );
  }

  @override
  State<AuditDateRangeDialog> createState() => _AuditDateRangeDialogState();
}

class _AuditDateRangeDialogState extends State<AuditDateRangeDialog> {
  late TextEditingController _startController;
  late TextEditingController _endController;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: widget.initialStartDate);
    _endController = TextEditingController(text: widget.initialEndDate);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    DateTime initial = DateTime.now();
    if (controller.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(controller.text.trim());
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: DefensysTokens.maroonOf(context),
              onPrimary: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => controller.text = formatted);
    }
  }

  void _applyPreset(int daysAgo) {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: daysAgo));
    String format(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    setState(() {
      _startController.text = format(start);
      _endController.text = format(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);

    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 18, color: DefensysTokens.maroonOf(context)),
                      const SizedBox(width: 8),
                      Text(
                        'Filter by Date Range',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Presets
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip('Today', () => _applyPreset(0)),
                  _presetChip('Last 7 Days', () => _applyPreset(7)),
                  _presetChip('Last 30 Days', () => _applyPreset(30)),
                  _presetChip('Last 90 Days', () => _applyPreset(90)),
                ],
              ),
              const SizedBox(height: 18),

              // Date Inputs
              Row(
                children: [
                  Expanded(
                    child: _buildDateField('Start Date', _startController),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateField('End Date', _endController),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _startController.clear();
                        _endController.clear();
                      });
                      widget.onApply('', '');
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Clear Dates',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          widget.onApply(
                            _startController.text.trim(),
                            _endController.text.trim(),
                          );
                          Navigator.of(context).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: DefensysTokens.maroonOf(context),
                        ),
                        child: const Text('Apply Filter'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildDateField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _pickDate(controller),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: DefensysTokens.borderOf(context)),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    controller.text.isEmpty ? 'YYYY-MM-DD' : controller.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: controller.text.isEmpty
                          ? const Color(0xFF94A3B8)
                          : DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
