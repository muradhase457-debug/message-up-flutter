import 'package:flutter/material.dart';

/// One menu entry for [ThreeDotMenu].
class ThreeDotMenuItem {
  const ThreeDotMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;
}

/// Reusable ⋮ slide-up menu used by the app bar, chat header, feed, etc.
/// Opens as a bottom sheet (thumb-friendly on phones) instead of a
/// tiny popup — same menu everywhere, one widget.
class ThreeDotMenu extends StatelessWidget {
  const ThreeDotMenu({
    super.key,
    required this.items,
    this.title,
  });

  final List<ThreeDotMenuItem> items;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More options',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    title!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              const SizedBox(height: 4),
              ...items.map((item) => ListTile(
                    leading: item.icon == null
                        ? null
                        : Icon(item.icon,
                            color: item.danger ? Colors.red : null),
                    title: Text(
                      item.label,
                      style: TextStyle(
                          color: item.danger ? Colors.red : null),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      item.onTap();
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
