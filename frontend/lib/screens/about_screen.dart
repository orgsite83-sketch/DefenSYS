import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('About DefenSYS'),
        backgroundColor: AppColors.maroon,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: AppColors.maroon,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.shield_rounded, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('DefenSYS',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('Version 1.0.0',
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _card([
              _sectionTitle('What is DefenSYS?'),
              const SizedBox(height: 8),
              _body(
                'DefenSYS is a cross-platform Capstone and PIT Management System designed for the '
                'Department of Information Technology. It centralizes academic period management, '
                'defense evaluation workflows, secure digital archiving, and curriculum analytics '
                'into one unified platform.',
              ),
            ]),
            const SizedBox(height: 16),
            _card([
              _sectionTitle('Key Features'),
              const SizedBox(height: 12),
              ...[
                (Icons.gavel_rounded, 'Defense Evaluation', 'Rubric-based grading with grade lock protection.'),
                (Icons.folder_special_rounded, 'Digital Vault', 'Secure document archiving with watermarking.'),
                (Icons.people_rounded, 'Peer Evaluation', 'Student-to-student criterion-based scoring.'),
                (Icons.bar_chart_rounded, 'Curriculum Analytics', 'Technology trend analysis from archived projects.'),
                (Icons.lock_rounded, 'Role-Based Access', 'Separate views for Admin, Faculty, and Students.'),
              ].map((f) => _featureRow(f.$1, f.$2, f.$3)),
            ]),
            const SizedBox(height: 16),
            _card([
              _sectionTitle('Development Stack'),
              const SizedBox(height: 12),
              _stackRow('Backend', 'Django (Python)'),
              _stackRow('Database', 'SQLite / PostgreSQL'),
              _stackRow('Mobile', 'Flutter (Dart)'),
              _stackRow('ML Engine', 'scikit-learn — TF-IDF + Naive Bayes'),
              _stackRow('Docs', 'PyPDF2, python-docx'),
            ]),
            const SizedBox(height: 16),
            _card([
              _sectionTitle('Developed By'),
              const SizedBox(height: 8),
              _body('Department of Information Technology\nCapstone Project — AY 2025–2026'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.gold, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'This system is intended for academic use only within the institution.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Center(
              child: Text('© 2026 DefenSYS. All rights reserved.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withOpacity(0.6))),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary));

  Widget _body(String text) => Text(text,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6));

  Widget _featureRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.maroon.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppColors.maroon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stackRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
