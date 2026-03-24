import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _aiCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();

  bool _loading = false;
  Map<String, dynamic>? _aiEstimate;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
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

  Future<void> _confirmEstimate() async {
    if (_aiEstimate == null) return;
    final dash = context.read<DashboardProvider>();
    await dash.addFood(
      _aiEstimate!['item'] as String,
      (_aiEstimate!['calories'] as num).toInt(),
      (_aiEstimate!['protein'] as num).toInt(),
      (_aiEstimate!['carbs'] as num).toInt(),
      (_aiEstimate!['fats'] as num).toInt(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${_aiEstimate!['item']} +${_aiEstimate!['calories']} kcal')),
      );
    }
    setState(() { _aiEstimate = null; _aiCtrl.clear(); });
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

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, dash, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log Food', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'DMSerifDisplay', color: AppColors.onSurface)),
                  const Text('Tell Gemini what you ate', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
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
              const Text('Describe your meal naturally', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 10),
              TextField(
                controller: _aiCtrl,
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. "2 rotis with dal, small bowl of rice..."',
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
                      : const Text('✨ Analyze with Gemini', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),

              // Quick add chips
              if (dash.commonMeals.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Quick add:', style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
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
            ],
          ),
        ),

        // ── AI Estimate Confirmation ──
        if (_aiEstimate != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gemini\'s Estimate:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
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
                          // Pre-fill manual tab with estimate
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
