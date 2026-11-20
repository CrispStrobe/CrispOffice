import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_window.dart';

/// One workspace action shared by the native and in-window File menus.
class StudioMenuAction {
  const StudioMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.shortcut,
    this.onSelected,
  });

  final String id;
  final String label;
  final IconData icon;
  final SingleActivator? shortcut;
  final VoidCallback? onSelected;

  PlatformMenuItem get nativeItem => PlatformMenuItem(
    label: label,
    shortcut: shortcut,
    onSelected: onSelected,
  );
}

/// A keyboard-accessible desktop File menu for Windows and Linux.
class StudioFileMenu extends StatelessWidget {
  const StudioFileMenu({super.key, required this.label, required this.groups});

  final String label;
  final List<List<StudioMenuAction>> groups;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    menuChildren: <Widget>[
      for (var index = 0; index < groups.length; index++) ...<Widget>[
        if (index > 0) const Divider(height: 9),
        for (final action in groups[index])
          MenuItemButton(
            key: ValueKey<String>('desktop-file-${action.id}'),
            leadingIcon: Icon(action.icon, size: 18),
            shortcut: action.shortcut,
            onPressed: action.onSelected,
            child: Text(action.label),
          ),
      ],
    ],
    builder: (BuildContext context, MenuController controller, Widget? child) =>
        TextButton(
          key: const ValueKey<String>('desktop-file-menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          onPressed: () {
            controller.isOpen ? controller.close() : controller.open();
          },
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
  );
}

/// Installs real macOS menus while keeping callbacks in the live workspace.
/// Other platforms use [StudioFileMenu] in the title bar.
class StudioNativeMenus extends StatelessWidget {
  const StudioNativeMenus({
    super.key,
    required this.fileLabel,
    required this.editLabel,
    required this.viewLabel,
    required this.windowLabel,
    required this.aboutLabel,
    required this.settingsLabel,
    required this.fileGroups,
    required this.editGroups,
    required this.viewGroups,
    required this.onAbout,
    required this.onSettings,
    required this.child,
  });

  final String fileLabel;
  final String editLabel;
  final String viewLabel;
  final String windowLabel;
  final String aboutLabel;
  final String settingsLabel;
  final List<List<StudioMenuAction>> fileGroups;
  final List<List<StudioMenuAction>> editGroups;
  final List<List<StudioMenuAction>> viewGroups;
  final VoidCallback onAbout;
  final VoidCallback onSettings;
  final Widget child;

  List<PlatformMenuItem> _groups(List<List<StudioMenuAction>> groups) =>
      <PlatformMenuItem>[
        for (final group in groups)
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              for (final action in group) action.nativeItem,
            ],
          ),
      ];

  @override
  Widget build(BuildContext context) {
    if (!StudioWindow.isMacOS) return child;
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'CrispOffice',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(label: aboutLabel, onSelected: onAbout),
                PlatformMenuItem(
                  label: settingsLabel,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onSettings,
                ),
              ],
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(label: fileLabel, menus: _groups(fileGroups)),
        PlatformMenu(label: editLabel, menus: _groups(editGroups)),
        PlatformMenu(
          label: viewLabel,
          menus: <PlatformMenuItem>[
            ..._groups(viewGroups),
            const PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: windowLabel,
          menus: const <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
