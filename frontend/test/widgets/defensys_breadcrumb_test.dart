import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/widgets/shadcn/defensys_breadcrumb.dart';
import 'package:defensys/theme/app_theme.dart';

void main() {
  group('DefensysBreadcrumb', () {
    testWidgets('renders single root item as current active page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefensysBreadcrumb(
              items: const [
                DefensysBreadcrumbItem(
                  label: 'Project Archive',
                  icon: Icon(LucideIcons.folderArchive, size: 14),
                  isCurrent: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Project Archive'), findsOneWidget);
      expect(find.byIcon(LucideIcons.folderArchive), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    testWidgets('renders multiple items with chevron separators and back button', (tester) async {
      bool backTapped = false;
      bool archiveTapped = false;
      bool yearTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DefensysBreadcrumb(
              onBack: () => backTapped = true,
              backLabel: 'Back',
              items: [
                DefensysBreadcrumbItem(
                  label: 'Project Archive',
                  icon: const Icon(LucideIcons.folderArchive, size: 14),
                  onTap: () => archiveTapped = true,
                ),
                DefensysBreadcrumbItem(
                  label: '2026-2027',
                  onTap: () => yearTapped = true,
                ),
                const DefensysBreadcrumbItem(
                  label: '1st Semester',
                  isCurrent: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Project Archive'), findsOneWidget);
      expect(find.text('2026-2027'), findsOneWidget);
      expect(find.text('1st Semester'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(backTapped, isTrue);

      await tester.tap(find.text('Project Archive'));
      await tester.pumpAndSettle();
      expect(archiveTapped, isTrue);

      await tester.tap(find.text('2026-2027'));
      await tester.pumpAndSettle();
      expect(yearTapped, isTrue);
    });

    testWidgets('renders cleanly in dark theme without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.mistDarkTheme,
          home: Scaffold(
            body: DefensysBreadcrumb(
              onBack: () {},
              items: const [
                DefensysBreadcrumbItem(label: 'Root'),
                DefensysBreadcrumbItem(label: 'Subfolder'),
                DefensysBreadcrumbItem(label: 'Active Leaf', isCurrent: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Root'), findsOneWidget);
      expect(find.text('Subfolder'), findsOneWidget);
      expect(find.text('Active Leaf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
