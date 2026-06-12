import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n_ext.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/offline_banner.dart';
import '../../../../services/notifications_provider.dart';
import '../../../../widgets/notifications_modal.dart';

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
          const SizedBox(width: 20),
          const _NotificationsBell(),
          const SizedBox(width: 20),
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

class _NotificationsBell extends ConsumerStatefulWidget {
  const _NotificationsBell();

  @override
  ConsumerState<_NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends ConsumerState<_NotificationsBell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).fetchNotifications();
    });
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const NotificationsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);

    return Badge(
      isLabelVisible: state.unreadCount > 0,
      label: Text(
        state.unreadCount.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: DefensysUi.primaryMaroon,
      child: IconButton(
        icon: const Icon(
          Icons.notifications_outlined,
          color: DefensysUi.steelGrey,
          size: 23,
        ),
        tooltip: 'Notifications',
        onPressed: () => _showNotifications(context),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  final DefensysAdminSection activeSection;
  final ValueChanged<DefensysAdminSection> onNavigate;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.activeSection,
    required this.onNavigate,
    required this.onLogout,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late bool _isUserManagementOpen;
  late bool _isSchedulingOpen;

  @override
  void initState() {
    super.initState();
    final inUserMgmt = widget.activeSection == DefensysAdminSection.userManagement ||
        widget.activeSection == DefensysAdminSection.studentTeams ||
        widget.activeSection == DefensysAdminSection.studentAcademicRecords;
    final inSched = widget.activeSection == DefensysAdminSection.scheduling ||
        widget.activeSection == DefensysAdminSection.defenseBoard ||
        widget.activeSection == DefensysAdminSection.defenseStages;

    _isUserManagementOpen = inUserMgmt;
    _isSchedulingOpen = inSched;

    if (inUserMgmt) {
      _isSchedulingOpen = false;
    } else if (inSched) {
      _isUserManagementOpen = false;
    }
  }

  @override
  void didUpdateWidget(_Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSection != oldWidget.activeSection) {
      final wasInUserMgmt = oldWidget.activeSection == DefensysAdminSection.userManagement ||
          oldWidget.activeSection == DefensysAdminSection.studentTeams ||
          oldWidget.activeSection == DefensysAdminSection.studentAcademicRecords;
      final nowInUserMgmt = widget.activeSection == DefensysAdminSection.userManagement ||
          widget.activeSection == DefensysAdminSection.studentTeams ||
          widget.activeSection == DefensysAdminSection.studentAcademicRecords;

      if (nowInUserMgmt && !wasInUserMgmt) {
        _isUserManagementOpen = true;
        _isSchedulingOpen = false;
      }

      final wasInSched = oldWidget.activeSection == DefensysAdminSection.scheduling ||
          oldWidget.activeSection == DefensysAdminSection.defenseBoard ||
          oldWidget.activeSection == DefensysAdminSection.defenseStages;
      final nowInSched = widget.activeSection == DefensysAdminSection.scheduling ||
          widget.activeSection == DefensysAdminSection.defenseBoard ||
          widget.activeSection == DefensysAdminSection.defenseStages;

      if (nowInSched && !wasInSched) {
        _isSchedulingOpen = true;
        _isUserManagementOpen = false;
      }
    }
  }

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
              padding: const EdgeInsets.only(top: 16),
              children: [
                const _SectionHeader(title: 'Dashboard'),
                _NavItem(
                  section: DefensysAdminSection.overview,
                  activeSection: widget.activeSection,
                  icon: Icons.show_chart_rounded,
                  label: l10n.navOverview,
                  onTap: widget.onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.academicPeriods,
                  activeSection: widget.activeSection,
                  icon: Icons.calendar_month_rounded,
                  label: l10n.navAcademicPeriods,
                  onTap: widget.onNavigate,
                ),
                const _SectionHeader(title: 'Management'),
                _NavItem(
                  section: DefensysAdminSection.userManagement,
                  activeSection: widget.activeSection,
                  icon: Icons.groups_2_rounded,
                  label: l10n.navUserManagement,
                  trailing: _isUserManagementOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  onTap: (_) {
                    setState(() {
                      _isUserManagementOpen = !_isUserManagementOpen;
                      if (_isUserManagementOpen) {
                        _isSchedulingOpen = false;
                      }
                    });
                  },
                ),
                if (_isUserManagementOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.userManagement,
                    activeSection: widget.activeSection,
                    icon: Icons.person_rounded,
                    label: l10n.navUserManagement,
                    onTap: widget.onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentTeams,
                    activeSection: widget.activeSection,
                    icon: Icons.groups_rounded,
                    label: l10n.navStudentTeams,
                    onTap: widget.onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.studentAcademicRecords,
                    activeSection: widget.activeSection,
                    icon: Icons.badge_rounded,
                    label: l10n.navStudentRecords,
                    onTap: widget.onNavigate,
                  ),
                ],
                _NavItem(
                  section: DefensysAdminSection.gradeCenter,
                  activeSection: widget.activeSection,
                  icon: Icons.grade_rounded,
                  label: l10n.navGradeCenter,
                  onTap: widget.onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.rubricEngine,
                  activeSection: widget.activeSection,
                  icon: Icons.checklist_rounded,
                  label: l10n.navRubricEngine,
                  onTap: widget.onNavigate,
                ),
                const _SectionHeader(title: 'Analytics & Audit'),
                _NavItem(
                  section: DefensysAdminSection.repositoryAudit,
                  activeSection: widget.activeSection,
                  icon: Icons.camera_alt_rounded,
                  label: l10n.navRepositoryAudit,
                  onTap: widget.onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.curriculumAnalytics,
                  activeSection: widget.activeSection,
                  icon: Icons.manage_search_rounded,
                  label: l10n.navCurriculumAnalytics,
                  onTap: widget.onNavigate,
                ),
                _NavItem(
                  section: DefensysAdminSection.auditCompliance,
                  activeSection: widget.activeSection,
                  icon: Icons.verified_user_outlined,
                  label: 'Audit Trail',
                  onTap: widget.onNavigate,
                ),
                const _SectionHeader(title: 'Operations'),
                _NavItem(
                  section: DefensysAdminSection.scheduling,
                  activeSection: widget.activeSection,
                  icon: Icons.event_note_rounded,
                  label: l10n.navScheduling,
                  trailing: _isSchedulingOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  onTap: (_) {
                    setState(() {
                      _isSchedulingOpen = !_isSchedulingOpen;
                      if (_isSchedulingOpen) {
                        _isUserManagementOpen = false;
                      }
                    });
                  },
                ),
                if (_isSchedulingOpen) ...[
                  _SubNavItem(
                    section: DefensysAdminSection.scheduling,
                    activeSection: widget.activeSection,
                    icon: Icons.auto_awesome_rounded,
                    label: l10n.navDefenseScheduler,
                    onTap: widget.onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseBoard,
                    activeSection: widget.activeSection,
                    icon: Icons.view_column_rounded,
                    label: l10n.navDefenseBoard,
                    onTap: widget.onNavigate,
                  ),
                  _SubNavItem(
                    section: DefensysAdminSection.defenseStages,
                    activeSection: widget.activeSection,
                    icon: Icons.layers_rounded,
                    label: l10n.navDefenseStages,
                    onTap: widget.onNavigate,
                  ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.09)),
          _UserProfileCard(onLogout: widget.onLogout),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  final VoidCallback onLogout;

  const _UserProfileCard({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DefensysUi.accentGold.withValues(alpha: 0.5),
                width: 1.5,
              ),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: const Center(
              child: Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Administrator',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  'Academic Portal',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFCA5A5), // Soft red accent
                size: 18,
              ),
              tooltip: 'Log Out',
              onPressed: onLogout,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(6),
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }
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
    final containerColor = selected
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: containerColor,
          child: InkWell(
            onTap: () => onTap(section),
            hoverColor: Colors.white.withValues(alpha: 0.05),
            child: Container(
              height: 46,
              padding: const EdgeInsets.only(left: 10, right: 14),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: selected ? DefensysUi.accentGold : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        color: color,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailing, color: color.withValues(alpha: 0.86), size: 18),
                  ],
                ],
              ),
            ),
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
    final color = selected ? DefensysUi.accentGold : Colors.white.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: selected ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
          child: InkWell(
            onTap: () => onTap(section),
            hoverColor: Colors.white.withValues(alpha: 0.03),
            child: Container(
              height: 38,
              padding: const EdgeInsets.only(left: 36, right: 14),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysUi.fontFamily,
                        color: color,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          'assets/logo-login-mark-48.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
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
