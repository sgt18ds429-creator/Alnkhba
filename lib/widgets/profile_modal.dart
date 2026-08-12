import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/activation_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/recording_provider.dart';
import '../screens/activation_screen.dart';

class ProfileModal extends StatelessWidget {
  const ProfileModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProfileModal(),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final Uri url = Uri.parse('https://unrivaled-belekoy-e397c4.netlify.app/privacy-policy.html');
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Privacy policy could not be opened');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح رابط سياسة الخصوصية', style: TextStyle(fontFamily: 'Cairo')),
          ),
        );
      }
    }
  }

  void _showAccountDeletionDialog(BuildContext context) {
    final activationProvider = Provider.of<ActivationProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final recordingProvider = Provider.of<RecordingProvider>(context, listen: false);
    bool deleting = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setDialogState) => PopScope(
          canPop: !deleting,
          child: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: Theme.of(stateContext).colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(stateContext).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'حذف التفعيل والبيانات',
                    style: TextStyle(
                      color: Theme.of(stateContext).colorScheme.onSurface,
                      fontFamily: 'Cairo',
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Text(
                'وفقاً لمعايير الخصوصية، هل أنت متأكد من رغبتك في حذف بيانات التفعيل الجارية ومسح المحادثات المحلية نهائياً؟\n\nسيؤدي هذا الإجراء إلى تسجيل الخروج الفوري وإلغاء التفعيل على هذا الجهاز.',
                style: TextStyle(
                  color: Theme.of(stateContext).colorScheme.onSurfaceVariant,
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting ? null : () => Navigator.pop(dialogContext),
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: Theme.of(stateContext).colorScheme.onSurfaceVariant,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: deleting
                      ? null
                      : () async {
                          setDialogState(() => deleting = true);

                          final deletionError = await activationProvider.deactivateSelf();
                          if (!dialogContext.mounted) return;
                          if (deletionError != null) {
                            setDialogState(() => deleting = false);
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(SnackBar(content: Text(deletionError)));
                            return;
                          }

                          // Cloud deletion has already succeeded. Attempt both
                          // local cleanups independently, then always leave the
                          // protected UI.
                          try {
                            await chatProvider.deleteAllLocalData();
                          } catch (_) {}
                          try {
                            await recordingProvider.deleteAllRecordings();
                          } catch (_) {}

                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const ActivationScreen()),
                            (route) => false,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(stateContext).colorScheme.error,
                    foregroundColor: Theme.of(stateContext).colorScheme.onError,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'حذف وتأكيد الإلغاء',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activationProvider = Provider.of<ActivationProvider>(context);
    final user = activationProvider.currentUser;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32.0)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32.0)),
              border: Border.all(color: const Color(0xFFC5A059).withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle for drag
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),

                Text(
                  'الملف الشخصي',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                if (user != null) ...[
                  _buildInfoRow(context, Icons.person_outline, 'الاسم', user.fullName),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    Icons.vpn_key_outlined,
                    'كود التفعيل',
                    user.activationCode,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    context,
                    Icons.timer_outlined,
                    'المدة المتبقية',
                    user.expiresAt == null || user.expiresAt == 0
                        ? 'غير محدودة'
                        : '${user.remainingDays} يوم',
                    valueColor: Theme.of(context).colorScheme.primary,
                  ),
                ] else ...[
                  Center(
                    child: Text(
                      'لا توجد بيانات مستخدم',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 16),

                // Privacy Policy Button
                ElevatedButton.icon(
                  onPressed: () => _openPrivacyPolicy(context),
                  icon: Icon(
                    Icons.privacy_tip_outlined,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  label: Text(
                    'سياسة الخصوصية',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 12),

                // Delete Account Button
                ElevatedButton.icon(
                  onPressed: () => _showAccountDeletionDialog(context),
                  icon: Icon(
                    Icons.person_remove_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 20,
                  ),
                  label: Text(
                    'حذف الحساب والبيانات',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String title,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12.0,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Theme.of(context).colorScheme.onSurface,
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
