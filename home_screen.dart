import 'package:flutter/material.dart';
import 'package:message_up/screens/admin_screen.dart';
import 'package:message_up/screens/calls_screen.dart';
import 'package:message_up/screens/chats_screen.dart';
import 'package:message_up/screens/feed_screen.dart';
import 'package:message_up/screens/profile_screen.dart';
import 'package:message_up/screens/settings_screen.dart';
import 'package:message_up/screens/status_screen.dart';
import 'package:message_up/services/admin_service.dart';
import 'package:message_up/services/auth_service.dart';
import 'package:message_up/widgets/three_dot_menu.dart';
import 'package:provider/provider.dart';

/// Home shell: bottom navigation + a top ⋮ menu.
/// Tabs: Chats / Status / Calls / Feed / Profile.
/// The Admin screen is reachable ONLY via the ⋮ menu and ONLY when the
/// signed-in account passes [AdminService.isAdmin].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    ChatsScreen(),
    StatusScreen(),
    CallsScreen(),
    FeedScreen(),
    ProfileScreen(),
  ];

  static const List<String> _titles = <String>[
    'Message Up',
    'Status',
    'Calls',
    'Feed',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AdminService>().isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          ThreeDotMenu(
            title: 'Message Up',
            items: [
              if (isAdmin)
                ThreeDotMenuItem(
                  label: 'Admin Panel',
                  icon: Icons.admin_panel_settings,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AdminScreen()),
                  ),
                ),
              ThreeDotMenuItem(
                label: 'Settings',
                icon: Icons.settings,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                ),
              ),
              ThreeDotMenuItem(
                label: 'Log out',
                icon: Icons.logout,
                danger: true,
                onTap: () async {
                  await context.read<AuthService>().signOut();
                },
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF075E54),
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.circle_outlined), label: 'Status'),
          BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Calls'),
          BottomNavigationBarItem(
              icon: Icon(Icons.dynamic_feed), label: 'Feed'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
