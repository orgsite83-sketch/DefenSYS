import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';
import '../branding/defensys_logo_mark.dart';

class LibraryHero extends StatelessWidget {
  const LibraryHero({super.key});

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 760;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 16, height: 2, color: const Color(0xFFD3993E)),
            const SizedBox(width: 8),
            Text(
              'EXPLORE STUDENT WORK',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.maroonTextOf(context),
                fontSize: 10,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'A new idea starts here.',
          style: DefensysTokens.pageTitle.copyWith(
            fontSize: desktop ? 34 : 29,
            height: 1.12,
            letterSpacing: -.9,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Discover student projects, research papers, posters, and videos.',
          style: DefensysTokens.body.copyWith(
            fontSize: 12,
            height: 1.6,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (desktop) ...[
          Row(
            children: [
              const DefensysLogoMark(
                size: 40,
                colorMode: DefensysLogoColorMode.brand,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DefenSYS',
                      style: DefensysTokens.sectionTitle.copyWith(
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      'Research repository',
                      style: DefensysTokens.caption.copyWith(
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const LibraryInstitutionMarks(),
            ],
          ),
          const SizedBox(height: 22),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 650) {
              return Row(
                children: [
                  Expanded(flex: 6, child: copy),
                  const SizedBox(width: 24),
                  const Expanded(
                    flex: 5,
                    child: SizedBox(height: 185, child: LibraryFormatArtwork()),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: 8),
                const Center(
                  child: SizedBox(
                    width: 255,
                    height: 125,
                    child: LibraryFormatArtwork(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class LibraryInstitutionMarks extends StatelessWidget {
  const LibraryInstitutionMarks({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo-ustp-trans.png',
          width: 28,
          height: 32,
          fit: BoxFit.contain,
          semanticLabel: 'USTP logo',
        ),
        const SizedBox(width: 7),
        Image.asset(
          'assets/logo-dit-seal.png',
          width: 31,
          height: 31,
          fit: BoxFit.contain,
          semanticLabel: 'Department of Information Technology seal',
        ),
      ],
    ),
  );
}

class LibraryAffiliationFooter extends StatelessWidget {
  const LibraryAffiliationFooter({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28),
    child: Column(
      children: [
        Divider(color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'USTP Oroquieta\nDepartment of Information Technology',
                style: DefensysTokens.caption.copyWith(
                  fontSize: 10,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const LibraryInstitutionMarks(),
          ],
        ),
      ],
    ),
  );
}

/// Lightweight native artwork; no network assets or video players in the hero.
class LibraryFormatArtwork extends StatelessWidget {
  const LibraryFormatArtwork({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 300,
        height: 175,
        child: Stack(
          children: [
            Positioned(
              left: 22,
              right: 1,
              top: 20,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DefensysTokens.isDark(context)
                      ? const Color(0xFF382624)
                      : const Color(0xFFF4E9E5),
                  borderRadius: const BorderRadius.all(
                    Radius.elliptical(150, 95),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 28,
              child: Transform.rotate(
                angle: -.14,
                child: Container(
                  width: 95,
                  height: 134,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A110A),
                    borderRadius: BorderRadius.circular(4),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF4B100D), width: 4),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'STUDENT\nRESEARCH',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFEDCF9D),
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                      Text(
                        'Ideas\nin print.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'Manuscript',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 96,
              top: 4,
              child: Transform.rotate(
                angle: .075,
                child: Container(
                  width: 110,
                  height: 147,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFD7CCBB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STUDENT WORK',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF443B32),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          color: const Color(0xFFE6D7C2),
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final item in [
                                (36.0, const Color(0xFF946F59)),
                                (57.0, const Color(0xFF7A110A)),
                                (43.0, const Color(0xFFB7996C)),
                              ])
                                Expanded(
                                  child: Container(
                                    height: item.$1,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: item.$2,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Project poster',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF443B32),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 78,
              child: Transform.rotate(
                angle: -.06,
                child: Container(
                  width: 141,
                  height: 84,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF394D4B),
                    border: Border.all(
                      color: const Color(0xFFFFFDF8),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          'Project video',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 20,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: 9,
                  height: 9,
                  color: const Color(0xFFD3993E),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
