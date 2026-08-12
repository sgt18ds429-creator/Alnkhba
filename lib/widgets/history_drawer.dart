import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/chat_provider.dart';
import '../providers/activation_provider.dart';
import '../screens/developer_screen.dart';
import '../widgets/profile_modal.dart';

class HistoryDrawer extends StatelessWidget {
  const HistoryDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Drawer(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF020814).withOpacity(0.95), // Deep Navy from prompt
            border: Border(
              left: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 1.0),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header (App Logo + Name)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF087CFF).withOpacity(0.1),
                          border: Border.all(color: const Color(0xFFD9A441).withOpacity(0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF087CFF).withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.school, color: Color(0xFFD9A441), size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مساعد نخبة الأشعة',
                              style: TextStyle(
                                color: Color(0xFFF5F7FA),
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Elite Radiology Assistant',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 10.0,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(color: const Color(0xFF38BDF8).withOpacity(0.2), height: 1),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    children: [
                      // New Chat
                      _buildDrawerButton(
                        context,
                        icon: Icons.add_circle_outline,
                        label: 'محادثة جديدة',
                        color: const Color(0xFF087CFF),
                        onTap: () {
                          final provider = Provider.of<ChatProvider>(context, listen: false);
                          provider.clearChat();
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Chat History Section
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'سجل المحادثات',
                          style: TextStyle(
                            color: Color(0xFFAAB7C8),
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      Consumer<ChatProvider>(
                        builder: (context, provider, child) {
                          if (provider.sessions.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                'لا توجد محادثات محفوظة',
                                style: TextStyle(color: Color(0xFF5A6B7C), fontSize: 12.0),
                              ),
                            );
                          }
                          return Column(
                            children: provider.sessions.take(5).map((session) {
                              final isActive = session.id == provider.currentSessionId;
                              final dateStr = DateFormat('yMMMd', 'ar').add_jm().format(
                                DateTime.fromMillisecondsSinceEpoch(session.createdAt),
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6.0),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? const Color(0xFF087CFF).withOpacity(0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10.0),
                                  border: Border.all(
                                    color: isActive
                                        ? const Color(0xFF087CFF).withOpacity(0.5)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    provider.loadSession(session);
                                    Navigator.pop(context);
                                  },
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  leading: Icon(
                                    Icons.chat_bubble_outline,
                                    color: isActive
                                        ? const Color(0xFF38BDF8)
                                        : const Color(0xFFAAB7C8),
                                    size: 16,
                                  ),
                                  title: Text(
                                    session.title,
                                    style: TextStyle(
                                      color: isActive
                                          ? const Color(0xFFF5F7FA)
                                          : const Color(0xFFAAB7C8),
                                      fontSize: 13.0,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    dateStr,
                                    style: TextStyle(
                                      color: const Color(0xFFAAB7C8).withOpacity(0.6),
                                      fontSize: 10.0,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.redAccent,
                                      size: 14,
                                    ),
                                    onPressed: () => _confirmDelete(context, provider, session.id),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      Divider(color: const Color(0xFF38BDF8).withOpacity(0.2), height: 1),
                      const SizedBox(height: 16),

                      // Radiology Topics Section
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'مواضيع الأشعة',
                          style: TextStyle(
                            color: Color(0xFFAAB7C8),
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _buildTopicItem(context, 'CT (المفراس الحلزوني)', Icons.album_outlined),
                      _buildTopicItem(context, 'MRI (الرنين المغناطيسي)', Icons.view_in_ar),
                      _buildTopicItem(context, 'X-Ray (الأشعة السينية)', Icons.accessibility_new),
                      _buildTopicItem(context, 'Radiation Protection', Icons.security),
                    ],
                  ),
                ),

                Divider(color: const Color(0xFF38BDF8).withOpacity(0.2), height: 1),

                // Bottom Settings / About
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      _buildDrawerButton(
                        context,
                        icon: Icons.settings_outlined,
                        label: 'الإعدادات / الملف الشخصي',
                        color: const Color(0xFFAAB7C8),
                        onTap: () {
                          Navigator.pop(context);
                          ProfileModal.show(context);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDrawerButton(
                        context,
                        icon: Icons.info_outline,
                        label: 'حول التطبيق (المطور)',
                        color: const Color(0xFFAAB7C8),
                        onTap: () {
                          _showDeveloperInfoDialog(context);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDrawerButton(
                        context,
                        icon: Icons.admin_panel_settings,
                        label: 'صفحة المطور',
                        color: const Color(0xFF087CFF),
                        onTap: () {
                          _showDeveloperAuthDialog(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ChatProvider provider, String sessionId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0A1D32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.redAccent.withOpacity(0.35)),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('حذف المحادثة', style: TextStyle(color: Color(0xFFF5F7FA), fontSize: 16)),
            ],
          ),
          content: const Text(
            'هل تريد حذف هذه المحادثة نهائياً من هذا الجهاز؟',
            style: TextStyle(color: Color(0xFFAAB7C8), fontSize: 13.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                provider.deleteSession(sessionId);
                Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: const Color(0xFF08182A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF5F7FA),
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicItem(BuildContext context, String topic, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF38BDF8), size: 18),
      title: Text(topic, style: const TextStyle(color: Color(0xFFF5F7FA), fontSize: 13.0)),
      dense: true,
      onTap: () {
        final provider = Provider.of<ChatProvider>(context, listen: false);
        provider.sendMessage("أخبرني المزيد عن $topic وكيفية عمله في المجال الطبي.");
        Navigator.pop(context);
      },
    );
  }

  void _showDeveloperInfoDialog(BuildContext context) {
    final parentContext = context;
    showDialog(
      context: parentContext,
      builder: (dialogContext) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0A1D32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3)),
          ),
          title: const Row(
            children: [
              Icon(Icons.developer_mode, color: Color(0xFFD9A441), size: 22),
              SizedBox(width: 8),
              Text(
                'مطور التطبيق',
                style: TextStyle(
                  color: Color(0xFFF5F7FA),
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
              const Text(
                'مطور التطبيق: عبدالرحمن حازم كريم',
                style: TextStyle(
                  color: Color(0xFFF5F7FA),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.telegram, size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  const Text(
                    'تليكرام: @rhk190',
                    style: TextStyle(color: Color(0xFFAAB7C8), fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.phone_android, size: 16, color: Color(0xFFD9A441)),
                  const SizedBox(width: 8),
                  const Text(
                    'واتساب: 07711918993',
                    style: TextStyle(color: Color(0xFFAAB7C8), fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'نرسم المستقبل بالأشعة والذكاء',
                style: TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: const Color(0xFF38BDF8).withOpacity(0.2)),
              const SizedBox(height: 8),
              // Developer Dashboard access for admin
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (parentContext.mounted) {
                    _showDeveloperAuthDialog(parentContext);
                  }
                },
                icon: const Icon(Icons.admin_panel_settings, color: Color(0xFF087CFF), size: 16),
                label: const Text(
                  'دخول لوحة التحكم (للمسؤول فقط)',
                  style: TextStyle(color: Color(0xFF087CFF), fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF087CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeveloperAuthDialog(BuildContext context) {
    final parentContext = context;
    final navigator = Navigator.of(parentContext);
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String? errorText;
    bool loading = false;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setDialogState) {
          Future<void> login() async {
            final email = emailController.text.trim();
            final password = passwordController.text;
            if (email.isEmpty || password.isEmpty) {
              setDialogState(() => errorText = 'يرجى إدخال البريد الإلكتروني وكلمة المرور');
              return;
            }
            setDialogState(() {
              loading = true;
              errorText = null;
            });
            final activationProvider = Provider.of<ActivationProvider>(
              parentContext,
              listen: false,
            );
            final error = await activationProvider.verifyDeveloperCredentials(
              email: email,
              password: password,
            );
            if (!dialogContext.mounted) return;
            if (error == null) {
              Navigator.of(dialogContext).pop();
              if (!navigator.mounted) return;
              // Close the drawer's local-history entry before opening the
              // privileged screen. Keep using the captured NavigatorState so
              // no disposed dialog context is reused.
              navigator.pop();
              navigator.push(MaterialPageRoute(builder: (context) => const DeveloperScreen()));
            } else {
              setDialogState(() {
                loading = false;
                errorText = 'تعذر تسجيل الدخول: $error';
              });
            }
          }

          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF0A1D32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_outline, color: Color(0xFFD9A441)),
                  SizedBox(width: 8),
                  Text(
                    'دخول صفحة المطور',
                    style: TextStyle(color: Color(0xFFF5F7FA), fontSize: 16),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'استخدم حساب المطور الموثق في Supabase. لا توجد كلمة مرور مخزنة داخل التطبيق.',
                    style: TextStyle(color: Color(0xFFAAB7C8), fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Color(0xFFF5F7FA), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'البريد الإلكتروني',
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFF08182A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    onSubmitted: (_) => login(),
                    style: const TextStyle(color: Color(0xFFF5F7FA), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'كلمة المرور',
                      filled: true,
                      fillColor: const Color(0xFF08182A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  onPressed: loading ? null : login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF087CFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('دخول'),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      emailController.dispose();
      passwordController.dispose();
    });
  }
}
