import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:message_up/services/admin_service.dart';
import 'package:message_up/utils/constants.dart';
import 'package:message_up/widgets/avatar_widget.dart';
import 'package:provider/provider.dart';

/// Admin panel. Reachable ONLY when [AdminService.isAdmin] is true.
/// The widget double-checks the gate before rendering anything: anyone
/// else sees "Not admin" and no admin data is queried at all.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AdminService>().isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Panel')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Not admin.\nThis panel is only for the admin account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.report), text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DashboardTab(),
          _UsersTab(),
          _ReportsTab(),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  // Cached once in initState: creating the Future in build() would
  // refetch the counts on every rebuild.
  late final Future<List<int>> _countsFuture;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _countsFuture = Future.wait([
      db
          .collection(AppConstants.usersCollection)
          .count()
          .get()
          .then((a) => a.count ?? 0),
      db
          .collection(AppConstants.chatsCollection)
          .count()
          .get()
          .then((a) => a.count ?? 0),
      db
          .collection(AppConstants.postsCollection)
          .count()
          .get()
          .then((a) => a.count ?? 0),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: _countsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final counts = snapshot.data ?? <int>[0, 0, 0];
        final cards = <Map<String, dynamic>>[
          {'label': 'Users', 'value': counts[0], 'icon': Icons.people},
          {'label': 'Chats', 'value': counts[1], 'icon': Icons.chat},
          {'label': 'Posts', 'value': counts[2], 'icon': Icons.dynamic_feed},
        ];
        return GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: cards
              .map((c) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(c['icon'] as IconData,
                              size: 32, color: const Color(0xFF075E54)),
                          const SizedBox(height: 8),
                          Text('${c['value']}',
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold)),
                          Text(c['label'] as String,
                              style:
                                  const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .orderBy('displayName')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load users.'));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No users yet.'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final email = (data['email'] as String?) ?? '';
            final isAdminUser = AdminService.isAdminEmail(email);
            return ListTile(
              leading: AvatarWidget(
                photoUrl: (data['photoUrl'] as String?)?.isNotEmpty == true
                    ? data['photoUrl'] as String
                    : null,
                name: (data['displayName'] as String?) ?? '',
              ),
              title: Text((data['displayName'] as String?) ?? ''),
              subtitle: Text(email),
              trailing: isAdminUser
                  ? const Chip(
                      label: Text('ADMIN'),
                      backgroundColor: Color(0xFFE8B84B))
                  : null,
            );
          },
        );
      },
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    // Reports are stored in `reports` — created by users via Report in
    // the web app / future report flow. Listing + resolving is admin-only.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
              child: Text('Reports collection not set up yet.'));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
              child: Text('No reports. All quiet. 🎉',
                  style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final resolved = (data['resolved'] as bool?) ?? false;
            return ListTile(
              leading: Icon(
                resolved ? Icons.check_circle : Icons.report,
                color: resolved ? Colors.green : Colors.red,
              ),
              title: Text((data['reason'] as String?) ?? 'Report'),
              subtitle: Text(
                  'By ${data['reporterId'] ?? '?'} · ${data['targetId'] ?? '?'}'),
              trailing: resolved
                  ? const Text('Resolved',
                      style: TextStyle(color: Colors.green))
                  : TextButton(
                      onPressed: () => docs[i]
                          .reference
                          .update(<String, dynamic>{'resolved': true}),
                      child: const Text('Resolve'),
                    ),
            );
          },
        );
      },
    );
  }
}
