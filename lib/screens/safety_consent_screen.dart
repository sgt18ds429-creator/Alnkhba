import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_screen.dart';

class SafetyConsentScreen extends StatefulWidget {
  const SafetyConsentScreen({super.key});

  static const String preferenceKey = 'eliteradiq_safety_consent_2026_08';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(preferenceKey) ?? false;
  }

  @override
  State<SafetyConsentScreen> createState() => _SafetyConsentScreenState();
}

class _SafetyConsentScreenState extends State<SafetyConsentScreen> {
  bool _understandsLimitations = false;
  bool _acceptsDataProcessing = false;
  bool _saving = false;

  Future<void> _continue() async {
    if (!_understandsLimitations || !_acceptsDataProcessing || _saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SafetyConsentScreen.preferenceKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ChatScreen()));
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://unrivaled-belekoy-e397c4.netlify.app/privacy-policy.html'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Privacy policy could not be opened');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح سياسة الخصوصية حالياً.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF0A2540), Color(0xFF020814)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: colors.primary.withOpacity(0.25)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 36, offset: Offset(0, 18)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.health_and_safety_outlined,
                            color: colors.primary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'قبل استخدام المساعد',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'EliteRadIq أداة تعليمية مولّدة بالذكاء الاصطناعي. قد تكون الإجابات أو تحليلات الصور غير دقيقة.',
                          style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        _ConsentTile(
                          value: _understandsLimitations,
                          onChanged: (value) => setState(() => _understandsLimitations = value),
                          title: 'أفهم أنه ليس تشخيصاً طبياً',
                          subtitle:
                              'لن أعتمد عليه كتقرير أشعة رسمي أو قرار علاجي، وسأراجع اختصاصياً مؤهلاً وبروتوكول المؤسسة.',
                        ),
                        const SizedBox(height: 12),
                        _ConsentTile(
                          value: _acceptsDataProcessing,
                          onChanged: (value) => setState(() => _acceptsDataProcessing = value),
                          title: 'أوافق على معالجة ما أرسله عبر الإنترنت',
                          subtitle:
                              'سأزيل اسم المريض ورقم الملف والوجه وأي بيانات تعريفية قبل إرسال صورة أو PDF أو تسجيل.',
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _openPrivacyPolicy,
                          icon: const Icon(Icons.open_in_new, size: 17),
                          label: const Text('قراءة سياسة الخصوصية'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _understandsLimitations && _acceptsDataProcessing && !_saving
                              ? _continue
                              : null,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.arrow_back_rounded),
                          label: const Text('أوافق وأتابع'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? colors.primary.withOpacity(0.09) : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? colors.primary.withOpacity(0.55) : colors.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: (next) => onChanged(next ?? false)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.onSurfaceVariant, height: 1.5, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
