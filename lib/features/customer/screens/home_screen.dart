import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/service_provider.dart';
import '../../../models/machine_model.dart';
import '../../../models/service_model.dart';
import '../../../engines/service_time_estimator.dart';
import '../../../services/engagement_customer_service.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServiceProvider>().loadServices();
      context.read<MachineProvider>().seedDefaultMachines();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final serviceProvider = context.watch<ServiceProvider>();
    final services = serviceProvider.services;
    final isServicesLoading = serviceProvider.isLoading;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth > 1100
              ? 1100.0
              : constraints.maxWidth;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: CustomScrollView(
                slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${user?.name ?? 'Customer'}! 👋',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              "Let's get your laundry done today.",
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLoyaltyPointsCard(user),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildSectionTitle('Quick Actions'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: _buildQuickActions(),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildCapacityView(),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildSectionTitle(
                'Our Services',
                onSeeAll: () => Navigator.pushNamed(
                  context,
                  '/customer/create-order',
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildServicesRow(
                services,
                isServicesLoading: isServicesLoading,
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _buildSectionTitle('Active Laundry Transactions'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(
              child: _buildActiveOrders(),
            ),
          ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
    );
  }

  Widget _buildSectionTitle(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all >',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyPointsCard(UserModel? user) {
    if (user == null) {
      return const SizedBox.shrink();
    }

    final engagementService = EngagementCustomerService();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: engagementService.balance(user.id),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final points = (data?['points'] as num?)?.toInt() ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, '/customer/loyalty'),
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark.withValues(alpha: 0.94),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -22,
                    top: -28,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 23,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Expanded(
                            child: Text(
                              'Loyalty Points',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$points',
                              style: const TextStyle(
                                fontSize: 31,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            TextSpan(
                              text: ' pts',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Your rewards balance',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 390;

        final cards = [
          _buildActionCard(
            icon: Icons.add_circle_outline_rounded,
            label: 'New Transaction',
            description: 'Create a new laundry transaction',
            color: AppColors.primary,
            onTap: () => Navigator.pushNamed(
              context,
              '/customer/create-order',
            ),
          ),
          _buildActionCard(
            icon: Icons.track_changes_rounded,
            label: 'Track Laundry',
            description: 'Check your current transaction status',
            color: AppColors.success,
            onTap: () => Navigator.pushNamed(
              context,
              '/customer/order-history',
            ),
          ),
        ];

        if (stacked) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: 10),
              cards[1],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 148,
                child: cards[0],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 148,
                child: cards[1],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 25, color: color),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 19,
                    color: color.withValues(alpha: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapacityView() {
    return StreamBuilder<List<MachineModel>>(
      stream: context.read<MachineProvider>().streamMachines(),
      builder: (context, snapshot) {
        final machines = snapshot.data ?? [];

        final washers = machines
            .where((m) => m.type == AppConstants.machineWasher)
            .toList();
        final dryers = machines
            .where((m) => m.type == AppConstants.machineDryer)
            .toList();

        final washerAvailable = washers.where((m) => m.isAvailable).length;
        final washerInUse = washers.where((m) => m.isInUse).length;
        final dryerAvailable = dryers.where((m) => m.isAvailable).length;
        final dryerInUse = dryers.where((m) => m.isInUse).length;

        final washerTotal = washers.length;
        final dryerTotal = dryers.length;

        final washerUtilization = washerTotal > 0
            ? washerInUse / washerTotal
            : 0.0;
        final dryerUtilization = dryerTotal > 0
            ? dryerInUse / dryerTotal
            : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Shop Capacity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${machines.length} Machines',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildCapacityCard(
              title: 'Washing Machines',
              icon: Icons.local_laundry_service_rounded,
              color: AppColors.processingColor,
              available: washerAvailable,
              inUse: washerInUse,
              total: washerTotal,
              utilization: washerUtilization,
            ),
            const SizedBox(height: 10),
            _buildCapacityCard(
              title: 'Dryers',
              icon: Icons.air_rounded,
              color: Colors.deepPurple,
              available: dryerAvailable,
              inUse: dryerInUse,
              total: dryerTotal,
              utilization: dryerUtilization,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCapacityCard({
    required String title,
    required IconData icon,
    required Color color,
    required int available,
    required int inUse,
    required int total,
    required double utilization,
  }) {
    final availability = total > 0 ? available / total : 0.0;

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$total Total',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildUtilizationRing(
                  percent: utilization,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 15),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: availability.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: color.withValues(alpha: 0.09),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildCapacityStat(
                  label: 'Available',
                  value: '$available',
                  color: AppColors.success,
                ),
                const Spacer(),
                _buildCapacityStat(
                  label: 'In Use',
                  value: '$inUse',
                  color: color,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapacityStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildUtilizationRing({
    required double percent,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${(percent * 100).round()}%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  IconData _serviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('dry') && !lower.contains('wash')) {
      return Icons.air_rounded;
    }
    return Icons.local_laundry_service_rounded;
  }

  Color _serviceAccentColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('dry') && !lower.contains('wash')) {
      return Colors.deepPurple;
    }
    if (lower.contains('wash') && lower.contains('dry')) {
      return AppColors.primary;
    }
    return AppColors.processingColor;
  }

  /// Presentation-only duration for the dashboard cards.
  /// Scheduling still uses the existing service/estimator values.
  int _displayDurationMinutes(ServiceModel service) {
    final lower = '${service.name} ${service.type}'.toLowerCase();
    final isWash = lower.contains('wash');
    final isDry = lower.contains('dry');
    if (isWash && isDry) {
      return ServiceTimeEstimator.minutesPerCycle * 2;
    }
    if (isWash || isDry) {
      return ServiceTimeEstimator.minutesPerCycle;
    }
    return service.estimatedMinutes;
  }

  Widget _buildServicesRow(
    List<ServiceModel> services, {
    bool isServicesLoading = false,
  }) {
    if (isServicesLoading && services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (services.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Center(
            child: Text(
              'No services available',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const cardHeight = 188.0;
        final maxWidth = constraints.maxWidth;
        final tripleWidth = (maxWidth - (gap * 2)) / 3;
        final cardWidth = maxWidth >= 720
            ? tripleWidth
            : (tripleWidth < 188 ? 200.0 : tripleWidth.clamp(188.0, 240.0));

        return SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _buildPremiumServiceCard(services[index]),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPremiumServiceCard(ServiceModel service) {
    final accentColor = _serviceAccentColor(service.name);
    final minutes = _displayDurationMinutes(service);

    return SizedBox.expand(
      child: Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          '/customer/create-order',
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.9),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildServiceIcon(_serviceIcon(service.name), accentColor),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppColors.textHint,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                service.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${service.pricePerKg.toStringAsFixed(0)}/cycle',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.success,
                ),
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildInfoBadge(
                    'Max ${service.maxKgPerCycle.toStringAsFixed(0)}kg',
                    accentColor,
                  ),
                  if (minutes > 0)
                    _buildInfoBadge(
                      '~$minutes min',
                      AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildServiceIcon(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
        ),
      ),
      child: Icon(
        icon,
        color: color,
        size: 23,
      ),
    );
  }

  Widget _buildInfoBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActiveOrders() {
    final userId = context.read<AuthProvider>().user?.id ?? '';

    if (userId.isEmpty) {
      return _buildEmptyState();
    }

    return StreamBuilder(
      stream: context.read<OrderProvider>().streamUserOrders(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Card(
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: Center(
                child: Text(
                  'Unable to load your laundry transactions. Please check your connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }

        final orders = snapshot.data ?? [];

        if (orders.isEmpty) {
          return _buildEmptyState();
        }

        final activeOrders =
            orders.where((o) => !o.status.isFinished).toList();

        if (activeOrders.isEmpty) {
          return Card(
            margin: EdgeInsets.zero,
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: Center(
                child: Text(
                  'No active laundry transactions',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }

        return Column(
          children: activeOrders.take(3).map((order) {
            return _buildTransactionCard(order);
          }).toList(),
        );
      },
    );
  }

  Widget _buildTransactionCard(dynamic order) {
    Color getStatusColor() {
      final status = order.status.value;

      if (status == 'Pending' || status == 'Payment Verified') {
        return AppColors.processingColor;
      }
      if (status == 'Washing') {
        return AppColors.primary;
      }
      if (status == 'Drying') {
        return Colors.deepPurple;
      }
      if (status == 'Ready For Pickup' ||
          status == 'Ready For Delivery' ||
          status == 'Completed') {
        return AppColors.success;
      }

      return AppColors.textSecondary;
    }

    String getStatusLabel() {
      final status = order.status.value;

      if (status == 'Pending' || status == 'Payment Verified') {
        return 'Pending';
      }
      if (status == 'Washing') {
        return 'Washing';
      }
      if (status == 'Drying') {
        return 'Drying';
      }
      if (status == 'Ready For Pickup') {
        return 'Ready for Pickup';
      }
      if (status == 'Ready For Delivery') {
        return 'Ready for Delivery';
      }
      if (status == 'Completed') {
        return 'Completed';
      }

      return status;
    }

    String? getEstimatedFinish() {
      if (order.estimatedFinishTime != null) {
        final diff =
            order.estimatedFinishTime!.difference(DateTime.now());

        if (diff.inMinutes > 0) {
          if (diff.inMinutes < 60) {
            return '${diff.inMinutes} min';
          }

          final hours = (diff.inMinutes / 60).ceil();
          return '$hours hr';
        }

        return 'Ready now';
      }

      return null;
    }

    final statusColor = getStatusColor();
    final estimatedFinish = getEstimatedFinish();

    return Card(
      elevation: 1.2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          '/customer/order-tracking',
          arguments: {'orderId': order.id},
        ),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 78,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Order #${order.displayNumber}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(
                          getStatusLabel(),
                          statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Service: ${order.serviceType ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (order.actualWeight != null &&
                        order.actualWeight! > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${order.actualWeight!.toStringAsFixed(0)} kg',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (estimatedFinish != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Est: $estimatedFinish',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 23,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_laundry_service_rounded,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Laundry Transactions Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              "You haven't placed any laundry transactions yet.\nOnce you do, they'll appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/customer/create-order',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text(
                  'Create Your First Order',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.primary : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: 0,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor:
              isDark ? Colors.grey[400] : Colors.grey[600],
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded),
              label: 'Transactions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
          onTap: (index) {
            if (index == 1) {
              Navigator.pushNamed(
                context,
                '/customer/order-history',
              );
            } else if (index == 2) {
              Navigator.pushNamed(
                context,
                '/customer/profile',
              );
            }
          },
        ),
      ),
    );
  }
}
