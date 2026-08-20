import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/brand.dart';
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
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSizes.spaceMd),
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: BrandColors.aquaSoft,
                backgroundImage:
                    user?.photoUrl != null && user!.photoUrl!.isNotEmpty
                        ? NetworkImage(user.photoUrl!)
                        : null,
                child: user?.photoUrl == null || user!.photoUrl!.isEmpty
                    ? const Icon(
                        Icons.person,
                        size: 50,
                        color: BrandColors.navy,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              user?.name ?? 'User',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Text(
              user?.email ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.spaceLg),
            Card(
              child: Column(
                children: [
                  _buildProfileTile(Icons.phone, 'Phone', user?.phone ?? 'Not set'),
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
            const SizedBox(height: AppSizes.spaceMd),
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined, color: BrandColors.navy),
                title: const Text('Delivery Location'),
                subtitle: Text(
                  user?.address?.fullAddress.trim().isNotEmpty == true
                      ? user!.address!.fullAddress
                      : 'Set your pickup & delivery address',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(
                  context,
                  '/customer/location-setup',
                  arguments: {'fromProfile': true},
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium, color: BrandColors.aqua),
                title: const Text('Premium Membership'),
                subtitle: const Text('Manage plan, benefits, and payment proof'),
                onTap: () => Navigator.pushNamed(context, '/customer/membership'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.stars, color: BrandColors.aqua),
                title: const Text('My Loyalty Points'),
                onTap: () => Navigator.pushNamed(context, '/customer/loyalty'),
              ),
            ),
            const SizedBox(height: AppSizes.spaceMd),
            CustomButton(
              text: 'Sign Out',
              isOutlined: true,
              textColor: BrandColors.error,
              borderColor: BrandColors.error,
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
      leading: Icon(icon, color: BrandColors.navy),
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