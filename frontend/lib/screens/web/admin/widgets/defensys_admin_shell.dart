import 'package:flutter/material.dart';

import '../../../../l10n/l10n_ext.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/offline_banner.dart';

export '../../../../widgets/status_badge.dart';

enum DefensysAdminSection {
  overview,
  academicPeriods,
  userManagement,
  studentTeams,
  studentAcademicRecords,
  gradeCenter,
  rubricEngine,
  repositoryAudit,
  curriculumAnalytics,
  auditCompliance,
  scheduling,
  defenseBoard,
  defenseStages,
}

class DefensysUi {
  static const sidebarWidth = DefensysTokens.sidebarWidth;
  static const minDesktopWidth = DefensysTokens.minDesktopWidth;
  static const topNavHeight = DefensysTokens.topNavHeight;
  static const contentPadding = DefensysTokens.contentPadding;

  static const fontFamily = DefensysTokens.fontFamily;
  static const primaryMaroon = DefensysTokens.maroon;
  static const primaryDark = DefensysTokens.maroonDark;
  static const accentGold = DefensysTokens.gold;
  static const techBlue = DefensysTokens.techBlue;
  static const steelGrey = DefensysTokens.steelGrey;
  static const bgLight = DefensysTokens.background;
  static const textDark = DefensysTokens.textDark;
  static const white = DefensysTokens.surface;

  static const successBg = DefensysTokens.successBg;
  static const successText = DefensysTokens.successText;
  static const successBorder = DefensysTokens.successBorder;
  static const warningBg = DefensysTokens.warningBg;
  static const warningText = DefensysTokens.warningText;
  static const warningBorder = DefensysTokens.warningBorder;
  static const infoBg = DefensysTokens.infoBg;
  static const infoText = DefensysTokens.infoText;
  static const infoBorder = DefensysTokens.infoBorder;
  static const neutralBg = DefensysTokens.neutralBg;
  static const neutralText = DefensysTokens.neutralText;
  static const neutralBorder = DefensysTokens.neutralBorder;

  static TextStyle get pageTitle => DefensysTokens.pageTitle;

  static TextStyle get sectionTitle => DefensysTokens.sectionTitle;

  static TextStyle get subtitle => DefensysTokens.subtitle;

  static TextStyle get tableHeader => DefensysTokens.tableHeader;

  static TextStyle get tableCell => DefensysTokens.tableCell;

  static BoxDecoration cardDecoration() => DefensysTokens.cardDecoration();

  static const switchInactiveTrack = DefensysTokens.switchInactiveTrack;

  static Widget flatSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
    Color activeTrackColor = primaryMaroon,
    double scale = 1.0,
  }) {
    final w = Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashRadius: 0,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(0),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return activeTrackColor;
        }
        return switchInactiveTrack;
      }),
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
    );
    if (scale == 1.0) {
      return w;
    }
    return Transform.scale(
      scale: scale,
      alignment: Alignment.centerLeft,
      child: w,
    );
  }
}

class DefensysAdminShell extends StatelessWidget {
  final DefensysAdminSection activeSection;
  final String activeSemesterLabel;
  final Widget child;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;
  final bool scrollContent;

  const DefensysAdminShell({
    super.key,
    required this.activeSection,
    required this.activeSemesterLabel,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
    this.scrollContent = true,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: DefensysUi.fontFamily),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= DefensysUi.minDesktopWidth;

          void handleNavigate(DefensysAdminSection section) {
            onNavigate(section);
            if (!isWide) {
              Navigator.of(context).pop();
            }
          }

          void handleLogout() {
            if (!isWide) {
              Navigator.of(context).pop();
            }
            onLogout();
          }

          final sidebar = _Sidebar(
            activeSection: activeSection,
            onNavigate: isWide ? onNavigate : handleNavigate,
            onLogout: handleLogout,
          );

          final contentColumn = Column(
            children: [
              _TopNav(
                activeSemesterLabel: activeSemesterLabel,
                showMenuButton: !isWide,
              ),
              Expanded(
                child: OfflineBanner(
                  child: scrollContent
                      ? SingleChildScrollView(
                          padding: DefensysUi.contentPadding,
                          child: child,
                        )
                      : child,
                ),
              ),
            ],
          );

          if (isWide) {
            return Scaffold(
              backgroundColor: DefensysUi.bgLight,
              body: Row(
                children: [
                  sidebar,
                  Expanded(child: contentColumn),
                ],
              ),
            );
          }

          return Scaffold(
            backgroundColor: DefensysUi.bgLight,
            drawer: Drawer(
              width: DefensysUi.sidebarWidth,
              child: sidebar,
            ),
            body: contentColumn,
          );
        },
      ),
    );
  }
}

class DefensysPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? actions;

  const DefensysPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: DefensysUi.primaryMaroon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(title, style: DefensysUi.pageTitle),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: DefensysUi.subtitle),
            ],
          ),
        ),
        if (actions != null) ...[const SizedBox(width: 20), actions!],
      ],
    );
  }
}

class DefensysCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  const DefensysCard({
    super.key,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: DefensysUi.cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _TopNav extends StatelessWidget {
  final String activeSemesterLabel;
  final bool showMenuButton;

  const _TopNav({
    required this.activeSemesterLabel,
    this.showMenuButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DefensysUi.topNavHeight,
      padding: EdgeInsets.only(
        left: showMenuButton ? 8 : 32,
        right: 40,
      ),
      decoration: BoxDecoration(
        color: DefensysUi.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          const SizedBox(width: 16),
          _SemesterPill(label: activeSemesterLabel),
          const SizedBox(width: 16),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: DefensysUi.primaryMaroon,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          const Text(
            'Administrator',
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              color: DefensysUi.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final DefensysAdminSection activeSection;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.activeSection,
    required this.onNavigate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: DefensysUi.sidebarWidth,
      color: DefensysUi.primaryMaroon,
      child: Column(
        children: [
          Container(
            height: 92,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const _BrandSeal(size: 40),
                const SizedBox(width: 14),
                const Text(
                  'DefenSYS',
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: DefensysUi.accentGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 20),
              children: [
                _NavItem(
                  section: DefensysAdminSection.overview,
                  activeSection: activeSection,
                  icon: Icons.show_chart_rounded,
                  label: l10n.navOverview,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.academicPeriods,
                  activeSection: activeSection,
                  icon: Icons.calendar_month_rounded,
                  label: l10n.navAcademicPeriods,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.userManagement,
                  activeSection: activeSection,
                  icon: Icons.groups_2_rounded,
                  label: l10n.navUserManagement,
                  trailing: Icons.keyboard_arrow_down_rounded,
                  onTap: onNavigate,
                ),
                if (_isUserManagementOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.userManagement,
                    activeSection: activeSection,
                    icon: Icons.person_rounded,
                    label: l10n.navUserManagement,
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentTeams,
                    activeSection: activeSection,
                    icon: Icons.groups_rounded,
                  label: l10n.navStudentTeams,
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentAcademicRecords,
                    activeSection: activeSection,
                    icon: Icons.badge_rounded,
                    label: l10n.navStudentRecords,
                    onTap: onNavigate,
                  ),
                ],
                _NavItem(
                  section: DefensysAdminSection.gradeCenter,
                  activeSection: activeSection,
                  icon: Icons.grade_rounded,
                  label: l10n.navGradeCenter,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.rubricEngine,
                  activeSection: activeSection,
                  icon: Icons.checklist_rounded,
                  label: l10n.navRubricEngine,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.repositoryAudit,
                  activeSection: activeSection,
                  icon: Icons.camera_alt_rounded,
                  label: l10n.navRepositoryAudit,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.curriculumAnalytics,
                  activeSection: activeSection,
                  icon: Icons.manage_search_rounded,
                  label: l10n.navCurriculumAnalytics,
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.auditCompliance,
                  activeSection: activeSection,
                  icon: Icons.verified_user_outlined,
                  label: 'Audit Trail',
                  onTap: onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.scheduling,
                  activeSection: activeSection,
                  icon: Icons.event_note_rounded,
                  label: l10n.navScheduling,
                  trailing: Icons.keyboard_arrow_down_rounded,
                  onTap: onNavigate,
                ),
                if (_isSchedulingOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.scheduling,
                    activeSection: activeSection,
                    icon: Icons.auto_awesome_rounded,
                    label: l10n.navDefenseScheduler,
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseBoard,
                    activeSection: activeSection,
                    icon: Icons.view_column_rounded,
                    label: l10n.navDefenseBoard,
                    onTap: onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseStages,
                    activeSection: activeSection,
                    icon: Icons.layers_rounded,
                    label: l10n.navDefenseStages,
                    onTap: onNavigate,
                  ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.09)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onLogout,
              hoverColor: Colors.white.withValues(alpha: 0.05),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFD1D5DB),
                      size: 18,
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        color: Color(0xFFD1D5DB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  bool get _isUserManagementOpen =>
      activeSection == DefensysAdminSection.userManagement ||
      activeSection == DefensysAdminSection.studentTeams ||
      activeSection == DefensysAdminSection.studentAcademicRecords;

  bool get _isSchedulingOpen =>
      activeSection == DefensysAdminSection.scheduling ||
      activeSection == DefensysAdminSection.defenseBoard ||
      activeSection == DefensysAdminSection.defenseStages;
}

class _NavItem extends StatelessWidget {
  final DefensysAdminSection section;
  final DefensysAdminSection activeSection;
  final IconData icon;
  final String label;
  final IconData? trailing;
  final ValueChanged<DefensysAdminSection> onTap;

  const _NavItem({
    required this.section,
    required this.activeSection,
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        section == activeSection ||
        (section == DefensysAdminSection.userManagement &&
            (activeSection == DefensysAdminSection.studentTeams ||
                activeSection ==
                    DefensysAdminSection.studentAcademicRecords)) ||
        (section == DefensysAdminSection.scheduling &&
            (activeSection == DefensysAdminSection.scheduling ||
                activeSection == DefensysAdminSection.defenseBoard ||
                activeSection == DefensysAdminSection.defenseStages));
    final color = selected ? DefensysUi.accentGold : const Color(0xFFD1D5DB);

    return Material(
      color: selected ? DefensysUi.primaryDark : Colors.transparent,
      child: InkWell(
        onTap: () => onTap(section),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    left: BorderSide(color: DefensysUi.accentGold, width: 4),
                  )
                : null,
          ),
          padding: EdgeInsets.only(left: selected ? 23 : 27, right: 24),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, color: color.withValues(alpha: 0.86), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubNavItem extends StatelessWidget {
  final DefensysAdminSection section;
  final DefensysAdminSection activeSection;
  final IconData icon;
  final String label;
  final ValueChanged<DefensysAdminSection> onTap;

  const _SubNavItem({
    required this.section,
    required this.activeSection,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = section == activeSection;
    final color = selected ? DefensysUi.accentGold : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(section),
        hoverColor: Colors.white.withValues(alpha: 0.04),
        child: Container(
          constraints: const BoxConstraints(minHeight: 39),
          padding: const EdgeInsets.fromLTRB(56, 8, 22, 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: DefensysUi.fontFamily,
                    color: color,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SemesterPill extends StatelessWidget {
  final String label;

  const _SemesterPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: DefensysUi.successBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: DefensysUi.fontFamily,
          color: DefensysUi.successText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BrandSeal extends StatelessWidget {
  final double size;

  const _BrandSeal({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        color: Colors.white,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: DefensysUi.primaryMaroon,
            child: Icon(
              Icons.shield_rounded,
              color: DefensysUi.accentGold,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
