import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../providers/soap_provider.dart';
import '../../../models/soap_model.dart';

import '../../../providers/auth_provider.dart';

class AdminSoapInventoryScreen extends StatefulWidget {
  const AdminSoapInventoryScreen({super.key});

  @override
  State<AdminSoapInventoryScreen> createState() =>
      _AdminSoapInventoryScreenState();
}

class _AdminSoapInventoryScreenState extends State<AdminSoapInventoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SoapProvider>().loadSoaps();
    });
  }

  Color _parseColorHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'detergent':
        return Icons.soap;
      case 'fabric conditioner':
        return Icons.checkroom;
      case 'bleach':
        return Icons.opacity;
      case 'laundry soap':
        return Icons.clean_hands;
      default:
        return Icons.local_laundry_service;
    }
  }

  void _showAddEditDialog({SoapModel? existingSoap}) {
    final nameController = TextEditingController(
      text: existingSoap?.name ?? '',
    );
    final brandController = TextEditingController(
      text: existingSoap?.brand ?? '',
    );
    final descriptionController = TextEditingController(
      text: existingSoap?.description ?? '',
    );
    final priceController = TextEditingController(
      text: existingSoap?.price.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: existingSoap?.stockQuantity.toString() ?? '0',
    );
    final colorController = TextEditingController(
      text: existingSoap?.colorHex ?? '#1565C0',
    );

    String selectedUnit = existingSoap?.unit ?? 'sachet';
    String selectedCategory = existingSoap?.category ?? 'Detergent';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingSoap != null ? 'Edit Soap' : 'Add Soap'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: nameController,
                      labelText: 'Soap Name',
                      hintText: 'e.g. Tide Original',
                      prefixIcon: const Icon(Icons.soap),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: brandController,
                      labelText: 'Brand',
                      hintText: 'e.g. Tide',
                      prefixIcon: const Icon(Icons.branding_watermark),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: descriptionController,
                      labelText: 'Description',
                      hintText: 'Short description',
                      maxLines: 2,
                      prefixIcon: const Icon(Icons.description),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: CustomTextField(
                            controller: priceController,
                            labelText: 'Price (₱)',
                            hintText: '0.00',
                            keyboardType: TextInputType.number,
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: selectedUnit,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'sachet',
                                child: Text('Sachet'),
                              ),
                              DropdownMenuItem(
                                value: 'bottle',
                                child: Text('Bottle'),
                              ),
                              DropdownMenuItem(
                                value: 'bar',
                                child: Text('Bar'),
                              ),
                              DropdownMenuItem(
                                value: 'box',
                                child: Text('Box'),
                              ),
                              DropdownMenuItem(
                                value: 'pack',
                                child: Text('Pack'),
                              ),
                            ],
                            onChanged: (v) =>
                                setDialogState(() => selectedUnit = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: stockController,
                      labelText: 'Stock Quantity',
                      hintText: '0',
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.inventory),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Detergent',
                          child: Text('Detergent'),
                        ),
                        DropdownMenuItem(
                          value: 'Fabric Conditioner',
                          child: Text('Fabric Conditioner'),
                        ),
                        DropdownMenuItem(
                          value: 'Bleach',
                          child: Text('Bleach'),
                        ),
                        DropdownMenuItem(
                          value: 'Laundry Soap',
                          child: Text('Laundry Soap'),
                        ),
                        DropdownMenuItem(
                          value: 'Stain Remover',
                          child: Text('Stain Remover'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedCategory = v!),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      controller: colorController,
                      labelText: 'Color (Hex)',
                      hintText: '#1565C0',
                      prefixIcon: const Icon(Icons.palette),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                CustomButton(
                  text: existingSoap != null ? 'Update' : 'Add',
                  isLoading: isSaving,
                  onPressed: () async {
                    if (nameController.text.isEmpty) return;
                    setDialogState(() => isSaving = true);

                    final provider = context.read<SoapProvider>();
                    if (existingSoap != null) {
                      final updated = existingSoap.copyWith(
                        name: nameController.text.trim(),
                        brand: brandController.text.trim(),
                        description: descriptionController.text.trim(),
                        price: double.tryParse(priceController.text) ?? 0,
                        unit: selectedUnit,
                        stockQuantity: int.tryParse(stockController.text) ?? 0,
                        stockStatus:
                            (int.tryParse(stockController.text) ?? 0) > 0
                            ? 'In Stock'
                            : 'Out of Stock',
                        category: selectedCategory,
                        colorHex: colorController.text.trim().isNotEmpty
                            ? colorController.text.trim()
                            : '#1565C0',
                      );
                      await provider.updateSoap(updated);
                    } else {
                      await provider.addSoap(
                        name: nameController.text.trim(),
                        brand: brandController.text.trim(),
                        description: descriptionController.text.trim(),
                        price: double.tryParse(priceController.text) ?? 0,
                        unit: selectedUnit,
                        stockQuantity: int.tryParse(stockController.text) ?? 0,
                        category: selectedCategory,
                        colorHex: colorController.text.trim().isNotEmpty
                            ? colorController.text.trim()
                            : '#1565C0',
                      );
                    }

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final soapProvider = context.watch<SoapProvider>();
    final soaps = soapProvider.soaps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soap Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => soapProvider.loadSoaps(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: soapProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : soaps.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.soap, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No soaps available',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add a new soap',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: soaps.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${soaps.length} soap(s)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${soaps.where((s) => s.isInStock).length} in stock',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final soap = soaps[index - 1];
                return _buildSoapCard(soap, soapProvider);
              },
            ),
    );
  }

  Widget _buildSoapCard(SoapModel soap, SoapProvider provider) {
    final color = _parseColorHex(soap.colorHex);
    final statusColor = soap.isOutOfStock 
        ? AppColors.error 
        : (soap.isLowStock ? Colors.orange : AppColors.success);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showAddEditDialog(existingSoap: soap),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Soap icon with brand color
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getCategoryIcon(soap.category),
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              // Soap info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          soap.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            soap.inventoryStatus.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${soap.brand} · ${soap.category}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          CurrencyHelper.formatSimple(soap.price),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '/${soap.unit}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Stock: ${soap.stockQuantity}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'restock') {
                    _showRestockDialog(soap);
                  } else if (value == 'toggle') {
                    await provider.toggleStockStatus(soap.id);
                  } else if (value == 'delete') {
                    _showDeleteConfirm(soap, provider);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'restock',
                    child: Row(
                      children: [
                        Icon(Icons.add_business, size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Text('Restock Inventory'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          soap.isActive
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(soap.isActive ? 'Mark Inactive' : 'Mark Active'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: AppColors.error),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRestockDialog(SoapModel soap) {
    final qtyController = TextEditingController();
    final adminId = context.read<AuthProvider>().user?.id ?? '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Restock ${soap.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Stock: ${soap.stockQuantity} ${soap.unit}(s)'),
              const SizedBox(height: 16),
              CustomTextField(
                controller: qtyController,
                labelText: 'Quantity to Add',
                hintText: 'e.g. 50',
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.add_shopping_cart),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            CustomButton(
              text: 'Add to Stock',
              isLoading: isSaving,
              onPressed: () async {
                final qty = int.tryParse(qtyController.text) ?? 0;
                if (qty <= 0) return;
                
                setDialogState(() => isSaving = true);
                final success = await context.read<SoapProvider>().restockSoap(
                  soapId: soap.id,
                  quantity: qty,
                  adminId: adminId,
                );
                
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Inventory updated!' : 'Failed to restock.'),
                      backgroundColor: success ? AppColors.success : AppColors.error,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(SoapModel soap, SoapProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Soap'),
        content: Text('Are you sure you want to delete "${soap.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await provider.deleteSoap(soap.id);
    }
  }
}
