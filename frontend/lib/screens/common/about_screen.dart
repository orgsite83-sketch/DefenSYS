import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';
import '../../widgets/branding/defensys_logo_mark.dart';
import '../../widgets/branding/institutional_brand.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DefensysTokens.backgroundOf(context),
    appBar: AppBar(
      title: const Text('About DefenSYS'),
      backgroundColor: DefensysTokens.surfaceOf(context),
      foregroundColor: DefensysTokens.textPrimaryOf(context),
      titleTextStyle: DefensysTokens.appBarTitle.copyWith(
        color: DefensysTokens.textPrimaryOf(context),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(
        bottom: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _card(context, [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DefensysLogoMark(
                      size: 48,
                      colorMode: DefensysTokens.isDark(context)
                          ? DefensysLogoColorMode.white
                          : DefensysLogoColorMode.brand,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DefenSYS',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          _body(context, 'Version 1.0.0'),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Divider(
                    height: 1,
                    color: DefensysTokens.borderOf(context),
                  ),
                ),
                const InstitutionalBrand(),
              ]),
              const SizedBox(height: 24),
              _card(context, [
                _sectionTitle(context, 'What is DefenSYS?'),
                const SizedBox(height: 8),
                _body(
                  context,
                  'DefenSYS is a cross-platform Capstone and PIT Management System designed for the '
                  'Department of Information Technology. It centralizes academic period management, '
                  'defense evaluation workflows, secure digital archiving, and curriculum analytics '
                  'into one unified platform.',
                ),
              ]),
              const SizedBox(height: 16),
              _card(context, [
                _sectionTitle(context, 'Key Features'),
                const SizedBox(height: 12),
                ...[
                  (
                    Icons.gavel_rounded,
                    'Defense Evaluation',
                    'Rubric-based grading with grade lock protection.',
                  ),
                  (
                    Icons.folder_special_rounded,
                    'Project Repository',
                    'Secure document archiving with watermarking.',
                  ),
                  (
                    Icons.people_rounded,
                    'Peer Evaluation',
                    'Student-to-student criterion-based scoring.',
                  ),
                  (
                    Icons.bar_chart_rounded,
                    'Curriculum Analytics',
                    'Technology trend analysis from archived projects.',
                  ),
                  (
                    Icons.lock_rounded,
                    'Role-Based Access',
                    'Separate views for Admin, Faculty, and Students.',
                  ),
                ].map((f) => _featureRow(context, f.$1, f.$2, f.$3)),
              ]),
              const SizedBox(height: 16),
              _card(context, [
                _sectionTitle(context, 'Development Stack'),
                const SizedBox(height: 12),
                _stackRow(context, 'Backend', 'Django (Python)'),
                _stackRow(context, 'Database', 'SQLite / PostgreSQL'),
                _stackRow(context, 'Mobile', 'Flutter (Dart)'),
                _stackRow(
                  context,
                  'ML Engine',
                  'scikit-learn — TF-IDF + Naive Bayes',
                ),
                _stackRow(context, 'Docs', 'PyPDF2, python-docx'),
              ]),
              const SizedBox(height: 16),
              _card(context, [
                _sectionTitle(context, 'Developed By'),
                const SizedBox(height: 8),
                _body(
                  context,
                  'Department of Information Technology\nCapstone Project — AY 2025–2026',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: DefensysTokens.goldOf(context),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _body(
                          context,
                          'This system is intended for academic use only within the institution.',
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  '© 2026 DefenSYS. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _card(BuildContext context, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: DefensysTokens.borderOf(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );

  Widget _body(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: DefensysTokens.textSecondaryOf(context),
      height: 1.6,
    ),
  );

  Widget _featureRow(
    BuildContext context,
    IconData icon,
    String title,
    String desc,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: DefensysTokens.maroonTextOf(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _stackRow(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
        ),
      ],
    ),
  );
}
