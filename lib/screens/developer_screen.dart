import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/activation_provider.dart';
import '../models/registered_user.dart';

class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  ActivationProvider? _activationProvider;
  bool _signedOutForBackground = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ActivationProvider>(context, listen: false);
      provider.refreshFromCloud();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _signedOutForBackground = true;
      unawaited(_activationProvider?.signOutDeveloper());
    } else if (state == AppLifecycleState.resumed && _signedOutForBackground) {
      _signedOutForBackground = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(Navigator.maybePop(context));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activationProvider = Provider.of<ActivationProvider>(context, listen: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_activationProvider?.signOutDeveloper());
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDeleteUser(BuildContext context, ActivationProvider provider, RegisteredUser user) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(
                'حذف تفعيل المستخدم',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف المستخدم "${user.fullName}"؟\nسيؤدي هذا إلى إلغاء التفعيل فوراً وطرده من التطبيق ليُطالب بالتسجيل مجدداً.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'Cairo',
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final error = await provider.deleteUser(user.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error ?? 'تم حذف تفعيل المستخدم (${user.fullName}) بنجاح',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: error == null
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'حذف وإلغاء التفعيل',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddUserDialog(BuildContext context, ActivationProvider provider) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController(text: provider.generateActivationCode());
    int selectedDurationDays = 365;
    bool loading = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setDialogState) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'إنشاء دعوة مستخدم',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'الاسم الثلاثي للطالب/المستخدم',
                        labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'كود التفعيل',
                        labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedDurationDays,
                      dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'مدة التفعيل',
                        labelStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 365,
                          child: Text('سنة واحدة (365 يوم)', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                        DropdownMenuItem(
                          value: 180,
                          child: Text('6 أشهر (180 يوم)', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('شهر واحد (30 يوم)', style: TextStyle(fontFamily: 'Cairo')),
                        ),
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            'تفعيل دائم (بدون انتهاء)',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedDurationDays = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final fullName = nameCtrl.text.trim();
                          final activationCode = codeCtrl.text.trim();
                          setDialogState(() => loading = true);
                          final err = await provider.addNewUserByAdmin(
                            fullName: fullName,
                            activationCode: activationCode,
                            durationDays: selectedDurationDays == 0 ? null : selectedDurationDays,
                          );
                          if (!context.mounted) return;
                          if (err == null && dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          } else if (dialogContext.mounted) {
                            setDialogState(() => loading = false);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                err ?? 'تم إنشاء دعوة التفعيل للمستخدم ($fullName) بنجاح',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: err == null
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'إنشاء الدعوة',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      codeCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A).withOpacity(0.8),
          elevation: 0,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.transparent),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'لوحة التحكم للمطور',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          actions: [
            Consumer<ActivationProvider>(
              builder: (context, provider, child) {
                return IconButton(
                  icon: Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
                  tooltip: 'مزامنة وتحديث سحابي',
                  onPressed: () async {
                    await provider.refreshFromCloud();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'تمت المزامنة والتحديث من السحابة بنجاح',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                          backgroundColor: Theme.of(context).colorScheme.tertiary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ],
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
            onPressed: () => Navigator.pop(context),
            tooltip: 'رجوع وتسجيل خروج الإدارة',
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            labelStyle: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            tabs: const [
              Tab(text: 'المستخدمون المسجلون'),
              Tab(text: 'أكواد التفعيل'),
            ],
          ),
        ),
        body: Consumer<ActivationProvider>(
          builder: (context, provider, child) {
            final users = provider.registeredUsers;
            final usedCodesMap = <String, int>{};
            for (var u in users) {
              usedCodesMap[u.activationCode] = (usedCodesMap[u.activationCode] ?? 0) + 1;
            }

            final filteredUsers = users.where((u) {
              if (_searchQuery.isEmpty) return true;
              return u.fullName.toLowerCase().contains(_searchQuery) ||
                  u.activationCode.toLowerCase().contains(_searchQuery);
            }).toList();

            return TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Registered Users
                _buildUsersTab(context, provider, filteredUsers, users.length),

                // Tab 2: Codes Overview
                _buildCodesTab(context, provider, usedCodesMap),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildUsersTab(
    BuildContext context,
    ActivationProvider provider,
    List<RegisteredUser> filteredUsers,
    int totalCount,
  ) {
    return Column(
      children: [
        // Top Stats & Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الدعوات والمستخدمون',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalCount مستخدم',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الأكواد المتاحة',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provider.allowedCodes.length} كود جاهز',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _showAddUserDialog(context, provider),
                icon: Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                label: Text(
                  'إنشاء دعوة تفعيل لمستخدم',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'بحث باسم المستخدم أو الكود...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),

        // List of Registered Users
        Expanded(
          child: RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            onRefresh: () async {
              await provider.refreshFromCloud();
            },
            child: filteredUsers.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'لا يوجد مستخدمون مسجلون حالياً',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontFamily: 'Cairo',
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      final isCurrentDevice = provider.currentUser?.id == user.id;
                      final dateStr = user.pending
                          ? 'بانتظار استخدام كود الدعوة'
                          : DateFormat(
                              'y/MM/dd - hh:mm a',
                              'ar',
                            ).format(DateTime.fromMillisecondsSinceEpoch(user.activatedAt));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrentDevice
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: isCurrentDevice ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                        ),
                                        child: Icon(
                                          user.pending
                                              ? Icons.mark_email_unread_outlined
                                              : Icons.person,
                                          color: Theme.of(context).colorScheme.primary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    user.fullName,
                                                    style: TextStyle(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                      fontFamily: 'Cairo',
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isCurrentDevice) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.primaryContainer,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'جهازك الحالي',
                                                      style: TextStyle(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        fontSize: 9,
                                                        fontFamily: 'Cairo',
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              user.pending ? dateStr : 'تاريخ التفعيل: $dateStr',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontSize: 10.5,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_calendar,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      tooltip: 'تعديل مدة التفعيل',
                                      onPressed: () =>
                                          _showEditDurationDialog(context, provider, user),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_forever,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      tooltip: 'حذف التفعيل',
                                      onPressed: () => _confirmDeleteUser(context, provider, user),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Code & Duration Bar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        user.pending ? 'كود الدعوة:' : 'كود التفعيل المستخدم:',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 11,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      Text(
                                        user.activationCode,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.secondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Divider(
                                    color: Theme.of(context).colorScheme.outlineVariant,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'مدة التفعيل:',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          fontSize: 11,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      _buildDurationBadge(user),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCodesTab(
    BuildContext context,
    ActivationProvider provider,
    Map<String, int> usedCodesMap,
  ) {
    final codes = provider.allowedCodes;

    return Column(
      children: [
        // Top Action Bar for Codes Tab
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'إجمالي الأكواد: ${codes.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddCodeDialog(context, provider),
                icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary, size: 18),
                label: Text(
                  'إنشاء كود جديد',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // List of Active Codes
        Expanded(
          child: codes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.vpn_key_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'لا توجد أكواد تفعيل مفعلة حالياً',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: codes.length,
                  itemBuilder: (context, index) {
                    final code = codes[index];
                    final usageCount = usedCodesMap[code] ?? 0;
                    final isUsed = usageCount > 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isUsed
                              ? Theme.of(context).colorScheme.tertiary.withOpacity(0.4)
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${index + 1}.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                code,
                                style: const TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isUsed
                                      ? const Color(0xFF10B981).withOpacity(0.15)
                                      : const Color(0xFF1E2D3E),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isUsed ? 'مُفعّل ($usageCount مرة)' : 'جاهز للتفعيل',
                                  style: TextStyle(
                                    color: isUsed
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFF94A3B8),
                                    fontSize: 10.5,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFEF4444),
                                  size: 20,
                                ),
                                tooltip: 'حذف كود التفعيل',
                                onPressed: () => _confirmDeleteCode(context, provider, code),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAddCodeDialog(BuildContext context, ActivationProvider provider) {
    final codeController = TextEditingController(text: provider.generateActivationCode());

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_task, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'إنشاء كود تفعيل جديد',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'استخدم الكود العشوائي الآمن أو أدخل كوداً من 12 محرفاً على الأقل:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'ELITE-XXXXXXXXXXXXXXXX',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8),
                    letterSpacing: 1.0,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontFamily: 'Cairo'),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final newCode = codeController.text.trim();
                final error = await provider.addActivationCode(newCode);
                if (!context.mounted) return;
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error, style: const TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                } else {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تم إنشاء كود التفعيل ($newCode) بنجاح',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'إنشاء الكود',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(codeController.dispose);
  }

  void _confirmDeleteCode(BuildContext context, ActivationProvider provider, String code) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              Text(
                'حذف كود التفعيل',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف كود التفعيل ($code)؟\nلن يتمكن أي مستخدم جديد من التسجيل باستخدام هذا الكود بعد الآن.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final error = await provider.deleteActivationCode(code);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        error ?? 'تم إلغاء كود التفعيل ($code) بنجاح',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: error == null
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'حذف الكود',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationBadge(RegisteredUser user) {
    if (user.pending) {
      return Builder(
        builder: (context) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'بانتظار التفعيل',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontSize: 10.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      );
    }

    if (user.expiresAt == null || user.expiresAt == 0) {
      return Builder(
        builder: (context) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'غير محدود (دائم)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.tertiary,
                fontSize: 10.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      );
    }

    if (user.isExpired) {
      return Builder(
        builder: (context) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'منتهي الصلاحية',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 10.5,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      );
    }

    final days = user.remainingDays;
    return Builder(
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'متبقي $days يوم',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 10.5,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  void _showEditDurationDialog(
    BuildContext context,
    ActivationProvider provider,
    RegisteredUser user,
  ) {
    final daysController = TextEditingController(
      text: (user.expiresAt == null || user.expiresAt == 0) ? '' : '${user.remainingDays}',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_calendar, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'تعديل مدة التفعيل',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المستخدم: ${user.fullName}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'اختر مدة التفعيل السريعة أو أدخل عدد الأيام:',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text(
                        '+30 يوم (شهر)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      onPressed: () {
                        daysController.text = '30';
                      },
                    ),
                    ActionChip(
                      label: const Text(
                        '+90 يوم (3 أشهر)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      onPressed: () {
                        daysController.text = '90';
                      },
                    ),
                    ActionChip(
                      label: const Text(
                        '+365 يوم (سنة)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                      onPressed: () {
                        daysController.text = '365';
                      },
                    ),
                    ActionChip(
                      label: const Text(
                        'غير محدود (دائم)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.tertiary.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                      onPressed: () {
                        daysController.text = 'infinity';
                      },
                    ),
                    ActionChip(
                      label: const Text(
                        'إنهاء التفعيل فوراً',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.error.withOpacity(0.2),
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                      onPressed: () {
                        daysController.text = '0';
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'Cairo',
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: 'عدد الأيام المتبقية',
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    hintText: 'مثال: 30 أو infinity',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final input = daysController.text.trim().toLowerCase();
                int? days;
                if (input == 'infinity' || input.isEmpty) {
                  days = null; // Unlimited
                } else {
                  days = int.tryParse(input);
                  if (days == null || days < 0 || days > 3650) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'أدخل رقماً من 0 إلى 3650 أو اكتب infinity',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                    return;
                  }
                }

                final error = await provider.updateUserDuration(user.id, days);
                if (!context.mounted) return;
                if (error == null && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error ?? 'تم تحديث مدة تفعيل (${user.fullName}) بنجاح',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: error == null
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'حفظ التعديل',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(daysController.dispose);
  }
}
