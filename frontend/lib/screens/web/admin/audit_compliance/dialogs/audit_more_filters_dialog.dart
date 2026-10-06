import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditMoreFiltersDialog extends StatefulWidget {
  final String currentTrack;
  final String currentYearLevel;
  final Function(String track, String yearLevel) onApply;

  const AuditMoreFiltersDialog({
    super.key,
    required this.currentTrack,
    required this.currentYearLevel,
    required this.onApply,
  });

  static void show(
    BuildContext context, {
    required String currentTrack,
    required String currentYearLevel,
    required Function(String track, String yearLevel) onApply,
  }) {
    showDialog(
      context: context,
      builder: (context) => AuditMoreFiltersDialog(
        currentTrack: currentTrack,
        currentYearLevel: currentYearLevel,
        onApply: onApply,
      ),
    );
  }

  @override
  State<AuditMoreFiltersDialog> createState() => _AuditMoreFiltersDialogState();
}

class _AuditMoreFiltersDialogState extends State<AuditMoreFiltersDialog> {
  late String _selectedScope;

  @override
  void initState() {
    super.initState();
    if (widget.currentTrack == 'capstone') {
      _selectedScope = 'capstone';
    } else if (widget.currentTrack == 'pit') {
      if (widget.currentYearLevel == '1st Year') {
        _selectedScope = 'pit_1';
      } else if (widget.currentYearLevel == '2nd Year') {
        _selectedScope = 'pit_2';
      } else if (widget.currentYearLevel == '3rd Year') {
        _selectedScope = 'pit_3';
      } else if (widget.currentYearLevel == '4th Year') {
        _selectedScope = 'pit_4';
      } else {
        _selectedScope = 'pit_all';
      }
    } else {
      _selectedScope = 'all';
    }
  }

  void _apply() {
    String track = '';
    String yearLevel = '';
    if (_selectedScope == 'capstone') {
      track = 'capstone';
    } else if (_selectedScope == 'pit_all') {
      track = 'pit';
    } else if (_selectedScope == 'pit_1') {
      track = 'pit';
      yearLevel = '1st Year';
    } else if (_selectedScope == 'pit_2') {
      track = 'pit';
      yearLevel = '2nd Year';
    } else if (_selectedScope == 'pit_3') {
      track = 'pit';
      yearLevel = '3rd Year';
    } else if (_selectedScope == 'pit_4') {
      track = 'pit';
      yearLevel = '4th Year';
    }
    widget.onApply(track, yearLevel);
    Navigator.of(context).pop();
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
                      Icon(Icons.tune_rounded, size: 18, color: DefensysTokens.maroonOf(context)),
                      const SizedBox(width: 8),
                      Text(
                        'Academic Scope Filters',
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

              Text(
                'Filter audit logs by program track and year level:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                ),
              ),
              const SizedBox(height: 14),

              // Options
              RadioListTile<String>(
                value: 'all',
                groupValue: _selectedScope,
                title: const Text('All Academic Scopes', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'capstone',
                groupValue: _selectedScope,
                title: const Text('Capstone Only', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'pit_all',
                groupValue: _selectedScope,
                title: const Text('All PIT (Project in IT)', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'pit_1',
                groupValue: _selectedScope,
                title: const Text('PIT – 1st Year', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'pit_2',
                groupValue: _selectedScope,
                title: const Text('PIT – 2nd Year', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'pit_3',
                groupValue: _selectedScope,
                title: const Text('PIT – 3rd Year', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),
              RadioListTile<String>(
                value: 'pit_4',
                groupValue: _selectedScope,
                title: const Text('PIT – 4th Year', style: TextStyle(fontSize: 13.5)),
                activeColor: DefensysTokens.maroonOf(context),
                dense: true,
                onChanged: (val) => setState(() => _selectedScope = val!),
              ),

              const SizedBox(height: 20),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: DefensysTokens.maroonOf(context),
                    ),
                    child: const Text('Apply Filter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
