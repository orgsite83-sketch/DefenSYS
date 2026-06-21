import 'package:flutter/material.dart';

import 'defensys_admin_shell.dart';

/// Rollover modal — white shell, reference toolbar + table (no peach tint).
class StudentRecordsRolloverModal extends StatelessWidget {
  const StudentRecordsRolloverModal({
    super.key,
    required this.useWarningChrome,
    required this.activeLabel,
    required this.totalCount,
    required this.missingCount,
    required this.searchQuery,
    required this.filtered,
    required this.rolloverSearchCtrl,
    required this.actions,
    required this.onPromoteAll,
    required this.onRetainAll,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onActionChanged,
    required this.onClose,
    required this.onConfirm,
    required this.nonDropCount,
    required this.rolloverHasTarget,
    required this.rolloverResult,
    required this.asInt,
    required this.hasCsvUploaded,
    required this.onUploadCsv,
    required this.onClearCsv,
    required this.hasValidationErrors,
  });

  final bool useWarningChrome;
  final String activeLabel;
  final int totalCount;
  final int missingCount;
  final String searchQuery;
  final List<Map<String, dynamic>> filtered;
  final TextEditingController rolloverSearchCtrl;
  final Map<String, String> actions;
  final VoidCallback onPromoteAll;
  final VoidCallback onRetainAll;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final void Function(String recordId, String? value) onActionChanged;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final int nonDropCount;
  final bool Function(Map<String, dynamic> row, String action) rolloverHasTarget;
  final String Function(Map<String, dynamic> row, String action) rolloverResult;
  final int? Function(dynamic v) asInt;

  final bool hasCsvUploaded;
  final VoidCallback onUploadCsv;
  final VoidCallback? onClearCsv;
  final bool hasValidationErrors;

  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _blue = DefensysUi.techBlue;
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  static const _rolloverLegendBg = Color(0xFFFEF3C7);
  static const _rolloverLegendBorder = Color(0xFFF59E0B);
  static const _rolloverLegendText = Color(0xFF92400E);
  static const _rolloverResultGreen = Color(0xFF15803D);
  static const _rolloverPromoteChipBg = Color(0xFFDCFCE7);
  static const _rolloverPromoteChipFg = Color(0xFF166534);
  static const _rolloverActionMaroon = Color(0xFF4A0E0E);
  static const _rolloverInk = Color(0xFF0F172A);
  static const _rolloverSecondary = Color(0xFF717171);
  static const _warningBannerBg = Color(0xFFFEE2E2);
  static const _rowStripe = Color(0xFFF9FAFB);

  static TextStyle get _colHdr => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _muted,
        fontFamily: DefensysUi.fontFamily,
      );

  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: rolloverSearchCtrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _muted,
            size: 20,
          ),
          hintText: 'Search by student name or ID...',
          hintStyle: const TextStyle(
            color: _muted,
            fontSize: 13,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _maroon),
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onSearchClear,
                )
              : null,
        ),
        onChanged: onSearchChanged,
      ),
    );
  }

  Widget _bulkActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onClearCsv != null) ...[
          OutlinedButton.icon(
            onPressed: onClearCsv,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Change File'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _maroon,
              side: const BorderSide(color: _maroon),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton(
          onPressed: onPromoteAll,
          style: FilledButton.styleFrom(
            backgroundColor: _maroon,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          child: const Text('Promote All'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onRetainAll,
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          child: const Text('Retain All'),
        ),
      ],
    );
  }

  Widget _actionDropdown(
    String recordKeyId,
    String action,
    Color actionColor,
    bool isNewStudent,
    bool notInCsv,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: action == 'promote' || action == 'create'
              ? _rolloverPromoteChipBg
              : action == 'retain'
                  ? Colors.white
                  : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: action == 'promote' || action == 'create'
                ? _rolloverPromoteChipFg.withValues(alpha: 0.35)
                : action == 'retain'
                    ? _blue.withValues(alpha: 0.45)
                    : _red.withValues(alpha: 0.4),
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: action,
            isDense: true,
            borderRadius: BorderRadius.circular(8),
            style: TextStyle(
              color: actionColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              fontFamily: DefensysUi.fontFamily,
            ),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: actionColor,
            ),
            items: [
              if (isNewStudent)
                const DropdownMenuItem(value: 'create', child: Text('Create'))
              else ...[
                const DropdownMenuItem(value: 'promote', child: Text('Promote')),
                const DropdownMenuItem(value: 'retain', child: Text('Retain')),
              ],
              const DropdownMenuItem(value: 'drop', child: Text('Drop')),
            ],
            onChanged: (value) => onActionChanged(recordKeyId, value),
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(bool isNew, bool notInCsv) {
    final label = isNew
        ? 'New Student'
        : notInCsv
            ? 'Not Enrolled'
            : 'Enrolled';
    final bg = isNew
        ? const Color(0xFFF3E8FF)
        : notInCsv
            ? const Color(0xFFF3F4F6)
            : const Color(0xFFD1FAE5);
    final fg = isNew
        ? const Color(0xFF6B21A8)
        : notInCsv
            ? const Color(0xFF4B5563)
            : const Color(0xFF065F46);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Material(
        color: Colors.white,
        elevation: 12,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 960,
          height: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 8, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Semester Rollover & Promotion',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _rolloverInk,
                              fontFamily: DefensysUi.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.rotate_right_rounded,
                                size: 16,
                                color: _muted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Target semester: $activeLabel',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (hasCsvUploaded)
                                Text(
                                  '$totalCount student${totalCount == 1 ? '' : 's'} in preview',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      color: _muted,
                    ),
                  ],
                ),
              ),
              if (!hasCsvUploaded)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 540,
                      padding: const EdgeInsets.all(36),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF9FAFB),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cloud_upload_outlined,
                              size: 44,
                              color: _maroon,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Upload Official Class List',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _rolloverInk,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Select the official enrollment CSV file (containing student rows and class metadata) for the target semester. The system will match registered student IDs to promote them, and skip those who did not enroll.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: _rolloverSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 26),
                          ElevatedButton.icon(
                            onPressed: onUploadCsv,
                            icon: const Icon(Icons.file_open_rounded, size: 18, color: Colors.white),
                            label: const Text('Select CSV File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _maroon,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _rolloverLegendBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _rolloverLegendBorder),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: _rolloverLegendText,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: _rolloverLegendText,
                                fontFamily: DefensysUi.fontFamily,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Verify the promotion list. ',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                TextSpan(text: 'Promoted/Create → new academic records in target semester. '),
                                TextSpan(text: 'Retain → same level. '),
                                TextSpan(text: 'Drop → excluded (their record will not be rolled over).'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _searchField()),
                      const SizedBox(width: 12),
                      _bulkActions(),
                    ],
                  ),
                ),
                if (searchQuery.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Showing ${filtered.length} of $totalCount students',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (hasValidationErrors) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _warningBannerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF87171)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: _red,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Some rows contain validation warnings (e.g. missing name for user creation). Correct the details in the CSV file and re-upload before confirming.',
                              style: TextStyle(
                                color: _red,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.search_off_rounded,
                                size: 36,
                                color: _muted,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No students match "$searchQuery"',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Scrollbar(
                          thumbVisibility: true,
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: const BoxDecoration(
                                  color: _rowStripe,
                                  border: Border(
                                    bottom: BorderSide(color: _line),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 20,
                                      child: Text('Student', style: _colHdr),
                                    ),
                                    Expanded(
                                      flex: 10,
                                      child: Text('ID Number', style: _colHdr),
                                    ),
                                    Expanded(
                                      flex: 10,
                                      child: Text('Type', style: _colHdr),
                                    ),
                                    Expanded(
                                      flex: 18,
                                      child: Text('Current', style: _colHdr),
                                    ),
                                    Expanded(
                                      flex: 12,
                                      child: Text('Action', style: _colHdr),
                                    ),
                                    Expanded(
                                      flex: 20,
                                      child: Text('Target Result', style: _colHdr),
                                    ),
                                  ],
                                ),
                              ),
                              ...filtered.asMap().entries.map((e) {
                                final index = e.key;
                                final row = e.value;
                                final record = Map<String, dynamic>.from(
                                  row['record'] as Map,
                                );
                                final isNew = row['is_new_student'] == true;
                                final notInCsv = row['not_in_csv'] == true;
                                
                                final recordKeyId = record['id'] != null 
                                    ? record['id'].toString() 
                                    : record['student_username'].toString();

                                final action = actions[recordKeyId] ?? row['action_default'] ?? 'promote';
                                final actionColor = switch (action) {
                                  'retain' => _blue,
                                  'drop' => _red,
                                  _ => _rolloverPromoteChipFg,
                                };

                                final valError = row['validation_error']?.toString();
                                final hasErr = valError != null && valError.isNotEmpty;

                                final resultText = rolloverResult(row, action);
                                final ok = action == 'drop' || (rolloverHasTarget(row, action) && !hasErr);
                                final resultColor = action == 'drop'
                                    ? _red
                                    : ok
                                        ? _rolloverResultGreen
                                        : _red;
                                final stripe =
                                    index.isEven ? Colors.white : _rowStripe;

                                return Container(
                                  decoration: BoxDecoration(
                                    color: stripe,
                                    border: const Border(
                                      bottom: BorderSide(color: _line),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 20,
                                        child: Text(
                                          record['student_name']?.toString() ??
                                              '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: _rolloverInk,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 10,
                                        child: Text(
                                          record['student_username']
                                                  ?.toString() ??
                                              '-',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _rolloverInk,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 10,
                                        child: _typeBadge(isNew, notInCsv),
                                      ),
                                      Expanded(
                                        flex: 18,
                                        child: Text(
                                          record['id'] != null
                                              ? '${record['year_level'] ?? '-'} | ${record['semester'] ?? '-'}'
                                              : 'No records yet',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: _rolloverSecondary,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 12,
                                        child: _actionDropdown(
                                          recordKeyId,
                                          action,
                                          actionColor,
                                          isNew,
                                          notInCsv,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 20,
                                        child: hasErr
                                            ? Row(
                                                children: [
                                                  const Icon(Icons.error_outline_rounded, color: _red, size: 16),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      valError,
                                                      style: const TextStyle(
                                                        color: _red,
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                resultText.replaceAll(' · ', ' | '),
                                                style: TextStyle(
                                                  color: resultColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                ),
              ],
              const Divider(height: 1, thickness: 1, color: _line),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onClose,
                      style: TextButton.styleFrom(
                        foregroundColor: _rolloverActionMaroon,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (hasCsvUploaded) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: hasValidationErrors ? null : onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rolloverActionMaroon,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          elevation: 2,
                          shadowColor: Colors.black26,
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Create Rollover Records ($nonDropCount)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
