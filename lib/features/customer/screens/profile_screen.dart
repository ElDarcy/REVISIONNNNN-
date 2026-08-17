import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../providers/auth_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(
                Icons.person,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user?.name ?? 'User',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(user?.email ?? '', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            Card(
              child: Column(
                children: [
                  _buildProfileTile(
                    Icons.phone,
                    'Phone',
                    user?.phone ?? 'Not set',
                  ),
                  _buildProfileTile(Icons.email, 'Email', user?.email ?? ''),
                  _buildProfileTile(
                    Icons.badge,
                    'Role',
                    user?.role.value.capitalize() ?? 'Customer',
                  ),
                  _buildProfileTile(
                    Icons.calendar_today,
                    'Member Since',
                    user?.createdAt != null
                        ? '${user!.createdAt.month}/${user.createdAt.year}'
                        : 'N/A',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Card(child: ListTile(leading: const Icon(Icons.workspace_premium), title: const Text('Premium Membership'), subtitle: const Text('Manage plan, benefits, and payment proof'), onTap: () => Navigator.pushNamed(context, '/customer/membership'))),
            Card(child: ListTile(leading: const Icon(Icons.stars), title: const Text('My Loyalty Points'), onTap: () => Navigator.pushNamed(context, '/customer/loyalty'))),
            const SizedBox(height: 12),
            CustomButton(
              text: 'Sign Out',
              isOutlined: true,
              textColor: AppColors.error,
              borderColor: AppColors.error,
              onPressed: () async {
                await authProvider.logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

extension StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
