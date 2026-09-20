import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

enum PortalWorkspaceRole { seller, admin }

class PortalWorkspaceScaffold extends StatelessWidget {
  const PortalWorkspaceScaffold({
    super.key,
    required this.role,
    required this.activePath,
    required this.child,
  });

  final PortalWorkspaceRole role;
  final String activePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final groups = _menuGroups(role);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              _CompactNavigation(groups: groups, activePath: activePath),
              Expanded(child: child),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: _Sidebar(groups: groups, activePath: activePath),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class PortalPage extends StatelessWidget {
  const PortalPage({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.trailing,
    this.maxWidth = 1180,
  });

  final String title;
  final String? eyebrow;
  final Widget? trailing;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.brandTeal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class PortalMetricCard extends StatelessWidget {
  const PortalMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.attention = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (hint != null) ...[
              const SizedBox(height: 3),
              Text(
                hint!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: attention
                      ? AppTheme.priceBurgundy
                      : AppTheme.brandTeal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PortalMetricGrid extends StatelessWidget {
  const PortalMetricGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class PortalSection extends StatelessWidget {
  const PortalSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

class PortalStatusBadge extends StatelessWidget {
  const PortalStatusBadge({
    super.key,
    required this.label,
    this.attention = false,
  });

  final String label;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final foreground = attention ? AppTheme.priceBurgundy : AppTheme.brandTeal;
    final background = attention
        ? const Color(0xFFF8EEEE)
        : const Color(0xFFEFF5F5);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class PortalComingSoonScreen extends StatelessWidget {
  const PortalComingSoonScreen({
    super.key,
    required this.role,
    required this.activePath,
    required this.title,
    required this.description,
    required this.items,
  });

  final PortalWorkspaceRole role;
  final String activePath;
  final String title;
  final String description;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return PortalWorkspaceScaffold(
      role: role,
      activePath: activePath,
      child: PortalPage(
        eyebrow: role == PortalWorkspaceRole.seller ? '판매자 센터' : '관리자',
        title: title,
        child: PortalSection(
          title: '준비 중',
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 18),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: AppTheme.brandTeal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '현재 API가 준비된 뒤 실제 데이터로 연결됩니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.groups, required this.activePath});

  final List<_PortalMenuGroup> groups;
  final String activePath;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.brandTeal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
        children: [
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              child: Text(
                group.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFB7D0D1),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            for (final item in group.items)
              _SidebarItem(item: item, selected: item.path == activePath),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.selected});

  final _PortalMenuItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? const Color(0xFF0B5A5F) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: () => context.go(item.path),
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD5E2E0),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (item.soon)
                  const Text(
                    '준비',
                    style: TextStyle(color: Color(0xFFB7D0D1), fontSize: 10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({required this.groups, required this.activePath});

  final List<_PortalMenuGroup> groups;
  final String activePath;

  @override
  Widget build(BuildContext context) {
    final items = groups.expand((group) => group.items);
    return ColoredBox(
      color: AppTheme.brandTeal,
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TextButton(
                  onPressed: () => context.go(item.path),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: item.path == activePath
                        ? const Color(0xFF0B5A5F)
                        : Colors.transparent,
                  ),
                  child: Text(item.label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PortalMenuGroup {
  const _PortalMenuGroup(this.label, this.items);

  final String label;
  final List<_PortalMenuItem> items;
}

class _PortalMenuItem {
  const _PortalMenuItem(this.label, this.path, this.icon, {this.soon = false});

  final String label;
  final String path;
  final IconData icon;
  final bool soon;
}

List<_PortalMenuGroup> _menuGroups(PortalWorkspaceRole role) {
  if (role == PortalWorkspaceRole.seller) {
    return const [
      _PortalMenuGroup('운영', [
        _PortalMenuItem('운영 홈', '/seller', Icons.dashboard_outlined),
        _PortalMenuItem('판매자 사이트', '/seller/storefront', Icons.storefront_outlined),
        _PortalMenuItem('내 카탈로그', '/seller/products', Icons.inventory_2_outlined),
        _PortalMenuItem('주문 관리', '/seller/orders', Icons.receipt_long_outlined),
      ]),
      _PortalMenuGroup('분석·도구', [
        _PortalMenuItem(
          '통계',
          '/seller/stats',
          Icons.bar_chart_outlined,
          soon: true,
        ),
        _PortalMenuItem(
          '알림',
          '/seller/alerts',
          Icons.notifications_none,
          soon: true,
        ),
        _PortalMenuItem(
          '저장 필터',
          '/seller/saved-filters',
          Icons.filter_alt_outlined,
          soon: true,
        ),
        _PortalMenuItem('작업 기록', '/seller/activity', Icons.history, soon: true),
      ]),
    ];
  }
  return const [
    _PortalMenuGroup('운영', [
      _PortalMenuItem('운영 홈', '/admin', Icons.dashboard_outlined),
      _PortalMenuItem('입점 관리', '/admin/sellers', Icons.storefront_outlined),
      _PortalMenuItem('주문 관리', '/admin/orders', Icons.receipt_long_outlined),
      _PortalMenuItem('카탈로그', '/admin/catalog', Icons.category_outlined),
      _PortalMenuItem('사용자', '/admin/users', Icons.people_outline),
      _PortalMenuItem('시스템 도구', '/admin/tools', Icons.build_outlined),
    ]),
    _PortalMenuGroup('분석·도구', [
      _PortalMenuItem('통계', '/admin/stats', Icons.bar_chart_outlined),
      _PortalMenuItem(
        '알림',
        '/admin/alerts',
        Icons.notifications_none,
        soon: true,
      ),
      _PortalMenuItem(
        '저장 필터',
        '/admin/saved-filters',
        Icons.filter_alt_outlined,
        soon: true,
      ),
      _PortalMenuItem(
        '감사 로그',
        '/admin/audit',
        Icons.manage_history,
        soon: true,
      ),
    ]),
  ];
}
