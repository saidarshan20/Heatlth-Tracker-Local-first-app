import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../services/image_food_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../main.dart' show activeTabNotifier;

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with TickerProviderStateMixin {
  late TabController _tabCtrl;
  // Entrance animation — replays every time Log tab becomes active
  late final AnimationController _enterCtrl;
  late final Animation<double> _enterAnim;

  final _aiCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _aiEstimate;
  Uint8List? _pickedImage; // compressed bytes of the food photo, if any

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _enterCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));
    _enterAnim = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _enterCtrl.forward();
    activeTabNotifier.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (activeTabNotifier.value == 1 && mounted) {
      _enterCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    activeTabNotifier.removeListener(_onTabChanged);
    _enterCtrl.dispose();
    _tabCtrl.dispose();
    _aiCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _protCtrl.dispose();
    _carbCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyzeWithGemini() async {
    if (_aiCtrl.text.trim().isEmpty) return;
    setState(() { _loading = true; _aiEstimate = null; });

    final result = await GeminiService.parseFood(_aiCtrl.text.trim());
    setState(() { _loading = false; _aiEstimate = result; });
  }

  Future<void> _pickAndAnalyzeImage(ImageSource source) async {
    final XFile? file = source == ImageSource.camera
        ? await ImageFoodService.captureFromCamera()
        : await ImageFoodService.pickFromGallery();
    if (file == null) return;

    setState(() { _loading = true; _aiEstimate = null; _pickedImage = null; });
    final compressed = await ImageFoodService.compress(file);
    setState(() { _pickedImage = compressed; });

    final hint = _aiCtrl.text.trim().isEmpty ? null : _aiCtrl.text.trim();
    final result = await ImageFoodService.parseFoodFromImage(compressed, hint: hint);
    if (!mounted) return;
    setState(() { _loading = false; _aiEstimate = result; });
    if (result == null) {
      final reason = ImageFoodService.lastError ?? 'unknown';
      final msg = switch (reason) {
        'missing_key' => '❌ Gemini key missing — check .env and do a full flutter run.',
        'quota'       => '❌ Gemini free-tier quota exhausted. Try a new key or wait ~24h.',
        'network'     => '❌ No internet — check your connection.',
        'parse'       => "❌ Couldn't read the photo. Try a clearer shot.",
        _             => "❌ Image parse failed: $reason",
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
    }
  }

  void _clearPickedImage() {
    setState(() { _pickedImage = null; });
  }

  Future<void> _confirmEstimate() async {
    if (_aiEstimate == null) return;
    final dash = context.read<DashboardProvider>();
    await dash.addFood(
      _aiEstimate!['item'] as String,
      (_aiEstimate!['calories'] as num).toInt(),
      (_aiEstimate!['protein'] as num).toInt(),
      (_aiEstimate!['carbs'] as num).toInt(),
      (_aiEstimate!['fats'] as num).toInt(),
      rawInput: _aiCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${_aiEstimate!['item']} +${_aiEstimate!['calories']} kcal')),
      );
    }
    setState(() { _aiEstimate = null; _aiCtrl.clear(); _pickedImage = null; });
  }

  Future<void> _addManual() async {
    if (_nameCtrl.text.isEmpty || _calCtrl.text.isEmpty) return;
    final dash = context.read<DashboardProvider>();
    await dash.addFood(
      _nameCtrl.text.trim(),
      int.tryParse(_calCtrl.text) ?? 0,
      int.tryParse(_protCtrl.text) ?? 0,
      int.tryParse(_carbCtrl.text) ?? 0,
      int.tryParse(_fatCtrl.text) ?? 0,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${_nameCtrl.text} added!')),
      );
    }
    _nameCtrl.clear(); _calCtrl.clear(); _protCtrl.clear(); _carbCtrl.clear(); _fatCtrl.clear();
  }

  void _openPinManager(DashboardProvider dash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PinManageSheet(onChanged: dash.refresh),
    );
  }

  void _openQuickAddManager(DashboardProvider dash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickAddManageSheet(
        meals: dash.commonMeals,
        onChanged: dash.refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, _) {
        return FadeTransition(
          opacity: _enterAnim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(_enterAnim),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Log Food', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                      const Text('Tell us what you ate — or snap a photo', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      TabBar(
                        controller: _tabCtrl,
                        indicatorColor: AppColors.primary,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.onSurfaceVariant,
                        labelStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 12, fontWeight: FontWeight.w600),
                        tabs: const [
                          Tab(text: '✨ AI Log'),
                          Tab(text: 'Manual'),
                          Tab(text: 'History'),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildAITab(dash),
                      _buildManualTab(),
                      _buildHistoryTab(dash),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAITab(DashboardProvider dash) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Describe your meal — or snap a photo', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 10),

              // ── Image pickers ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _pickAndAnalyzeImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.primary),
                      label: const Text('Camera', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _pickAndAnalyzeImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_rounded, size: 16, color: AppColors.primary),
                      label: const Text('Gallery', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Thumbnail of picked image (if any) ──
              if (_pickedImage != null) ...[
                const SizedBox(height: 10),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _pickedImage!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6, right: 6,
                      child: GestureDetector(
                        onTap: _clearPickedImage,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _aiCtrl,
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: _pickedImage != null
                      ? 'Optional hint: "3 rotis not 2", "small portion"…'
                      : 'e.g. "2 rotis with dal, small bowl of rice..."',
                  hintStyle: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surfaceContainerHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.outline)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.outline)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _analyzeWithGemini,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                      : const Text('✨ Analyze', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),

              // ── Pinned meals ──
              if (dash.pinnedMeals.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('📌 Pinned:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _openPinManager(dash),
                      child: const Icon(Icons.edit_outlined, size: 15, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: dash.pinnedMeals.map((m) {
                    return GestureDetector(
                      onLongPress: () => _openPinManager(dash),
                      child: ActionChip(
                        avatar: const Text('📌', style: TextStyle(fontSize: 12)),
                        label: Text(
                          '${m['name']} · ${m['calories']} kcal',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                        onPressed: () async {
                          await dash.addFood(
                            m['name'] as String,
                            (m['calories'] as num).toInt(),
                            (m['protein'] as num).toInt(),
                            (m['carbs'] as num).toInt(),
                            (m['fats'] as num).toInt(),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('✅ ${m['name']} +${m['calories']} kcal')),
                            );
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],

              // ── Quick add (common meals) ──
              if (dash.commonMeals.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Quick add:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _openQuickAddManager(dash),
                      child: const Icon(Icons.edit_outlined, size: 15, color: AppColors.onSurfaceVariant),
                    ),
                    if (dash.pinnedMeals.isEmpty) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _openPinManager(dash),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin_outlined, size: 13, color: AppColors.onSurfaceVariant),
                            SizedBox(width: 3),
                            Text('Pin meals', style: TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: dash.commonMeals.map((m) {
                    return ActionChip(
                      label: Text(m['name'] as String, style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: AppColors.outline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                      onPressed: () async {
                        await dash.addFood(
                          m['name'] as String, (m['calories'] as num).toInt(),
                          (m['protein'] as num).toInt(), (m['carbs'] as num).toInt(), (m['fats'] as num).toInt(),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('✅ ${m['name']} +${m['calories']} kcal')),
                          );
                        }
                      },
                    );
                  }).toList(),
                ),
              ],

              // ── Empty state: no pinned, no quick ──
              if (dash.pinnedMeals.isEmpty && dash.commonMeals.isEmpty) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _openPinManager(dash),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.push_pin_outlined, size: 15, color: AppColors.onSurfaceVariant),
                        SizedBox(width: 8),
                        Text('Pin meals for quick logging', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                        Spacer(),
                        Icon(Icons.chevron_right, size: 16, color: AppColors.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── AI Estimate Confirmation ──
        if (_aiEstimate != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI Estimate:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('${_aiEstimate!['item']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                const SizedBox(height: 6),
                Text(
                  '~${_aiEstimate!['calories']} kcal  ·  P:${_aiEstimate!['protein']}g  ·  C:${_aiEstimate!['carbs']}g  ·  F:${_aiEstimate!['fats']}g',
                  style: const TextStyle(fontSize: 13, color: AppColors.primary),
                ),
                const SizedBox(height: 6),
                const Text('Is this right?', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirmEstimate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('✅ Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _nameCtrl.text = _aiEstimate!['item'] as String;
                          _calCtrl.text = '${_aiEstimate!['calories']}';
                          _protCtrl.text = '${_aiEstimate!['protein']}';
                          _carbCtrl.text = '${_aiEstimate!['carbs']}';
                          _fatCtrl.text = '${_aiEstimate!['fats']}';
                          setState(() { _aiEstimate = null; });
                          _tabCtrl.animateTo(1);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.outline),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('✏️ Edit', style: TextStyle(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildManualTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            children: [
              _field('Food name', _nameCtrl),
              _field('Calories (kcal)', _calCtrl, numeric: true),
              _field('Protein (g)', _protCtrl, numeric: true),
              _field('Carbs (g)', _carbCtrl, numeric: true),
              _field('Fat (g)', _fatCtrl, numeric: true),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addManual,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Add Entry', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
            decoration: InputDecoration(
              filled: true, fillColor: AppColors.surfaceContainerHigh,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.outline)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.outline)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(DashboardProvider dash) {
    if (dash.foodEntries.isEmpty) {
      return const Center(child: Text('No food logged today.', style: TextStyle(color: AppColors.onSurfaceVariant)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dash.foodEntries.length,
      itemBuilder: (context, i) {
        final e = dash.foodEntries[i];
        return Dismissible(
          key: ValueKey(e['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
          onDismissed: (_) {
            final deletedEntry = e;
            dash.deleteFood(e['id'] as int);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🗑️ ${e['item']} deleted'),
                action: SnackBarAction(
                  label: 'Undo',
                  textColor: AppColors.primary,
                  onPressed: () async {
                    await dash.addFood(
                      deletedEntry['item'] as String,
                      deletedEntry['calories'] as int,
                      deletedEntry['protein'] as int,
                      deletedEntry['carbs'] as int,
                      deletedEntry['fats'] as int,
                    );
                  },
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          },
          child: GestureDetector(
            onTap: () => _showEditFoodDialog(context, dash, e),
            child: FoodEntryTile(
              name: e['item'] as String,
              cal: e['calories'] as int,
              p: e['protein'] as int,
              c: e['carbs'] as int,
              f: e['fats'] as int,
            ),
          ),
        );
      },
    );
  }

  void _showEditFoodDialog(BuildContext context, DashboardProvider dash, Map<String, dynamic> entry) {
    final nameCtrl = TextEditingController(text: entry['item'] as String);
    final calCtrl = TextEditingController(text: '${entry['calories']}');
    final protCtrl = TextEditingController(text: '${entry['protein']}');
    final carbCtrl = TextEditingController(text: '${entry['carbs']}');
    final fatCtrl = TextEditingController(text: '${entry['fats']}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Entry', style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _editField('Food name', nameCtrl),
              _editField('Calories', calCtrl, numeric: true),
              _editField('Protein (g)', protCtrl, numeric: true),
              _editField('Carbs (g)', carbCtrl, numeric: true),
              _editField('Fat (g)', fatCtrl, numeric: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              await dash.updateFood(
                entry['id'] as int,
                nameCtrl.text.trim(),
                int.tryParse(calCtrl.text) ?? 0,
                int.tryParse(protCtrl.text) ?? 0,
                int.tryParse(carbCtrl.text) ?? 0,
                int.tryParse(fatCtrl.text) ?? 0,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✏️ ${nameCtrl.text} updated!')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, {bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
          filled: true, fillColor: AppColors.surfaceContainerHigh,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Pin Manage Bottom Sheet
// ─────────────────────────────────────────────
class _PinManageSheet extends StatefulWidget {
  final Future<void> Function() onChanged;
  const _PinManageSheet({required this.onChanged});

  @override
  State<_PinManageSheet> createState() => _PinManageSheetState();
}

class _PinManageSheetState extends State<_PinManageSheet> {
  List<Map<String, dynamic>> _pinned = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;

  // Manual add state
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  bool _showManualForm = false;
  bool _llmLoading = false;
  Map<String, dynamic>? _llmEstimate;

  // Edit state
  int? _editingId;
  final _editNameCtrl = TextEditingController();
  final _editCalCtrl = TextEditingController();
  final _editProtCtrl = TextEditingController();
  final _editCarbCtrl = TextEditingController();
  final _editFatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _protCtrl.dispose();
    _carbCtrl.dispose();
    _fatCtrl.dispose();
    _editNameCtrl.dispose();
    _editCalCtrl.dispose();
    _editProtCtrl.dispose();
    _editCarbCtrl.dispose();
    _editFatCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pinned = await DatabaseService.getPinnedMeals();
    final suggestions = await DatabaseService.getSuggestedMealsForPinning();
    if (!mounted) return;
    setState(() {
      _pinned = pinned;
      _suggestions = suggestions;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final pinned = await DatabaseService.getPinnedMeals();
    final suggestions = await DatabaseService.getSuggestedMealsForPinning();
    if (!mounted) return;
    setState(() { _pinned = pinned; _suggestions = suggestions; });
    await widget.onChanged();
  }

  Future<void> _unpin(int id) async {
    await DatabaseService.removePinnedMeal(id);
    await _refresh();
  }

  Future<void> _removeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove all pinned?', style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Remove All'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseService.removeAllPinnedMeals();
    await _refresh();
  }

  Future<void> _pinSuggestion(Map<String, dynamic> meal) async {
    await DatabaseService.addPinnedMeal(
      meal['name'] as String,
      (meal['calories'] as num).toInt(),
      (meal['protein'] as num).toInt(),
      (meal['carbs'] as num).toInt(),
      (meal['fats'] as num).toInt(),
    );
    await _refresh();
  }

  Future<void> _getLlmEstimate() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() { _llmLoading = true; _llmEstimate = null; });
    final result = await GeminiService.parseFood(name);
    if (!mounted) return;
    setState(() { _llmLoading = false; _llmEstimate = result; });
  }

  Future<void> _confirmLlm() async {
    if (_llmEstimate == null) return;
    await DatabaseService.addPinnedMeal(
      _llmEstimate!['item'] as String,
      (_llmEstimate!['calories'] as num).toInt(),
      (_llmEstimate!['protein'] as num).toInt(),
      (_llmEstimate!['carbs'] as num).toInt(),
      (_llmEstimate!['fats'] as num).toInt(),
    );
    _nameCtrl.clear();
    setState(() { _llmEstimate = null; _showManualForm = false; });
    await _refresh();
  }

  Future<void> _addManually() async {
    final name = _nameCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text) ?? 0;
    if (name.isEmpty || cal == 0) return;
    await DatabaseService.addPinnedMeal(
      name, cal,
      int.tryParse(_protCtrl.text) ?? 0,
      int.tryParse(_carbCtrl.text) ?? 0,
      int.tryParse(_fatCtrl.text) ?? 0,
    );
    _nameCtrl.clear(); _calCtrl.clear(); _protCtrl.clear(); _carbCtrl.clear(); _fatCtrl.clear();
    setState(() { _showManualForm = false; _llmEstimate = null; });
    await _refresh();
  }

  void _startEdit(Map<String, dynamic> meal) {
    _editNameCtrl.text = meal['name'] as String;
    _editCalCtrl.text = '${meal['calories']}';
    _editProtCtrl.text = '${meal['protein']}';
    _editCarbCtrl.text = '${meal['carbs']}';
    _editFatCtrl.text = '${meal['fats']}';
    setState(() { _editingId = meal['id'] as int; });
  }

  Future<void> _saveEdit() async {
    if (_editingId == null) return;
    await DatabaseService.updatePinnedMeal(
      _editingId!,
      _editNameCtrl.text.trim(),
      int.tryParse(_editCalCtrl.text) ?? 0,
      int.tryParse(_editProtCtrl.text) ?? 0,
      int.tryParse(_editCarbCtrl.text) ?? 0,
      int.tryParse(_editFatCtrl.text) ?? 0,
    );
    setState(() { _editingId = null; });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(width: 36, height: 4,
                        decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99))),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text('📌 Manage Pinned Meals',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                        const Spacer(),
                        if (_pinned.isNotEmpty)
                          TextButton(
                            onPressed: _removeAll,
                            child: const Text('Remove All', style: TextStyle(fontSize: 11, color: AppColors.error)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.outline),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [

                        // ── Pinned list ──
                        if (_pinned.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('No pinned meals yet. Pin one below!',
                                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant.withValues(alpha: 0.7))),
                          )
                        else
                          ..._pinned.map((meal) {
                            final isEditing = _editingId == meal['id'];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(14),
                                  border: isEditing
                                      ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: isEditing
                                    ? _buildEditForm()
                                    : _buildPinnedRow(meal),
                              ),
                            );
                          }),

                        const SizedBox(height: 16),

                        // ── Suggestions ──
                        if (_suggestions.isNotEmpty) ...[
                          const Text('Add from your history',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6, runSpacing: 6,
                            children: _suggestions.map((meal) {
                              final alreadyPinned = _pinned.any((p) => p['name'] == meal['name']);
                              return ActionChip(
                                avatar: Text(alreadyPinned ? '✅' : '➕', style: const TextStyle(fontSize: 12)),
                                label: Text(
                                  '${meal['name']} · ${meal['calories']} kcal',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: alreadyPinned ? AppColors.onSurfaceVariant : AppColors.onSurface,
                                  ),
                                ),
                                backgroundColor: alreadyPinned ? AppColors.surfaceContainerHigh : Colors.transparent,
                                side: BorderSide(
                                  color: alreadyPinned ? AppColors.outline.withValues(alpha: 0.5) : AppColors.outline,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                                onPressed: alreadyPinned ? null : () => _pinSuggestion(meal),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Add new ──
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Add a meal to pin',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _nameCtrl,
                                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                                decoration: InputDecoration(
                                  hintText: 'Meal name...',
                                  hintStyle: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                                  filled: true, fillColor: AppColors.surfaceContainer,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                onChanged: (_) {
                                  if (_llmEstimate != null) setState(() => _llmEstimate = null);
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _llmLoading ? null : _getLlmEstimate,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.surface,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: _llmLoading
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                                          : const Text('✨ Get from LLM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => setState(() { _showManualForm = !_showManualForm; _llmEstimate = null; }),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppColors.outline),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text(
                                        _showManualForm ? 'Hide form' : 'Add manually',
                                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // LLM result
                              if (_llmEstimate != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_llmEstimate!['item'] as String,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_llmEstimate!['calories']} kcal · P:${_llmEstimate!['protein']}g · C:${_llmEstimate!['carbs']}g · F:${_llmEstimate!['fats']}g',
                                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _confirmLlm,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Text('📌 Pin this', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Manual form
                              if (_showManualForm) ...[
                                const SizedBox(height: 12),
                                _miniField('Calories (kcal)', _calCtrl),
                                _miniField('Protein (g)', _protCtrl),
                                _miniField('Carbs (g)', _carbCtrl),
                                _miniField('Fat (g)', _fatCtrl),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _addManually,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('📌 Pin meal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPinnedRow(Map<String, dynamic> meal) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meal['name'] as String,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              const SizedBox(height: 2),
              Text(
                '${meal['calories']} kcal · P:${meal['protein']}g · C:${meal['carbs']}g · F:${meal['fats']}g',
                style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.onSurfaceVariant),
          onPressed: () => _startEdit(meal),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.push_pin_outlined, size: 16, color: AppColors.error.withValues(alpha: 0.7)),
          onPressed: () => _unpin(meal['id'] as int),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _miniField('Name', _editNameCtrl, isText: true),
        _miniField('Calories', _editCalCtrl),
        _miniField('Protein (g)', _editProtCtrl),
        _miniField('Carbs (g)', _editCarbCtrl),
        _miniField('Fat (g)', _editFatCtrl),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() { _editingId = null; }),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.outline),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _saveEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniField(String label, TextEditingController ctrl, {bool isText = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: isText ? TextInputType.text : TextInputType.number,
        style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
          filled: true, fillColor: AppColors.surfaceContainer,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Quick Add Manage Bottom Sheet
// ─────────────────────────────────────────────
class _QuickAddManageSheet extends StatefulWidget {
  final List<Map<String, dynamic>> meals;
  final Future<void> Function() onChanged;
  const _QuickAddManageSheet({required this.meals, required this.onChanged});

  @override
  State<_QuickAddManageSheet> createState() => _QuickAddManageSheetState();
}

class _QuickAddManageSheetState extends State<_QuickAddManageSheet> {
  late List<Map<String, dynamic>> _meals;
  int? _editingId;

  final _editNameCtrl = TextEditingController();
  final _editCalCtrl = TextEditingController();
  final _editProtCtrl = TextEditingController();
  final _editCarbCtrl = TextEditingController();
  final _editFatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _meals = List.from(widget.meals);
  }

  @override
  void dispose() {
    _editNameCtrl.dispose();
    _editCalCtrl.dispose();
    _editProtCtrl.dispose();
    _editCarbCtrl.dispose();
    _editFatCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final updated = await DatabaseService.getCommonMeals(minCount: 0, limit: 100);
    if (!mounted) return;
    setState(() => _meals = updated);
    await widget.onChanged();
  }

  void _startEdit(Map<String, dynamic> meal) {
    _editNameCtrl.text = meal['name'] as String;
    _editCalCtrl.text = '${meal['calories']}';
    _editProtCtrl.text = '${meal['protein']}';
    _editCarbCtrl.text = '${meal['carbs']}';
    _editFatCtrl.text = '${meal['fats']}';
    setState(() => _editingId = meal['id'] as int);
  }

  Future<void> _saveEdit() async {
    if (_editingId == null) return;
    await DatabaseService.updateCommonMeal(
      _editingId!,
      _editNameCtrl.text.trim(),
      int.tryParse(_editCalCtrl.text) ?? 0,
      int.tryParse(_editProtCtrl.text) ?? 0,
      int.tryParse(_editCarbCtrl.text) ?? 0,
      int.tryParse(_editFatCtrl.text) ?? 0,
    );
    setState(() => _editingId = null);
    await _refresh();
  }

  Future<void> _delete(Map<String, dynamic> meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove from Quick Add?',
            style: TextStyle(color: AppColors.onSurface, fontFamily: 'DMSans', fontSize: 15)),
        content: Text(
          '"${meal['name']}" will no longer appear in Quick Add. It can re-appear if you log it frequently again.',
          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseService.deleteCommonMeal(meal['id'] as int);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(99))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Text('⚡ Quick Add Meals',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                  const Spacer(),
                  Text('${_meals.length} items',
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'These appear automatically based on your meal history. Edit or remove any you don\'t want.',
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1, color: AppColors.outline),
            Expanded(
              child: _meals.isEmpty
                  ? const Center(
                      child: Text('No quick add meals yet.\nLog meals frequently and they\'ll appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: _meals.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final meal = _meals[i];
                        final isEditing = _editingId == meal['id'];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                            border: isEditing
                                ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
                                : null,
                          ),
                          child: isEditing ? _buildEditForm() : _buildRow(meal),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> meal) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meal['name'] as String,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              const SizedBox(height: 2),
              Text(
                '${meal['calories']} kcal · P:${meal['protein']}g · C:${meal['carbs']}g · F:${meal['fats']}g · logged ${meal['log_count']}×',
                style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.onSurfaceVariant),
          onPressed: () => _startEdit(meal),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.delete_outline, size: 16, color: AppColors.error.withValues(alpha: 0.7)),
          onPressed: () => _delete(meal),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('Name', _editNameCtrl, isText: true),
        _field('Calories', _editCalCtrl),
        _field('Protein (g)', _editProtCtrl),
        _field('Carbs (g)', _editCarbCtrl),
        _field('Fat (g)', _editFatCtrl),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _editingId = null),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.outline),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _saveEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool isText = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: isText ? TextInputType.text : TextInputType.number,
        style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
          filled: true, fillColor: AppColors.surfaceContainer,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
        ),
      ),
    );
  }
}
