import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class WorkflowStepProgress extends StatelessWidget {
  const WorkflowStepProgress({
    super.key,
    required this.currentStep,
    required this.labels,
    required this.compactLabels,
  });
  final int currentStep;
  final List<String> labels, compactLabels;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final labels = compact ? compactLabels : this.labels;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 20,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Row(
          children: [
            for (int i = 1; i <= labels.length; i++) ...[
              if (i > 1)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 16),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              Expanded(
                child: Semantics(
                  label: '${labels[i - 1]}, step $i of ${labels.length}',
                  selected: currentStep == i,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: currentStep == i
                              ? DefensysTokens.textPrimaryOf(context)
                              : null,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: currentStep == i
                                ? DefensysTokens.textPrimaryOf(context)
                                : DefensysTokens.borderOf(context),
                          ),
                        ),
                        child: i < currentStep
                            ? Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: DefensysTokens.textPrimaryOf(context),
                              )
                            : Text(
                                '$i',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: currentStep == i
                                      ? DefensysTokens.surfaceOf(context)
                                      : DefensysTokens.textSecondaryOf(context),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labels[i - 1],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 12 : 13,
                            fontWeight: currentStep == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: currentStep == i
                                ? DefensysTokens.textPrimaryOf(context)
                                : DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
