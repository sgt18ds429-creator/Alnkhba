import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/activation_provider.dart';
import 'safety_consent_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 15))
      ..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    final provider = Provider.of<ActivationProvider>(context, listen: false);
    final error = await provider.activate(
      fullName: _nameController.text,
      code: _codeController.text,
    );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = error;
      });

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(error, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFC53030),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        // Successfully activated, navigate to main chat screen
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const SafetyConsentScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    }
  }

  Future<void> _openExternal(Uri uri, String failureMessage) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('External application did not open');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF020814),
        body: Stack(
          children: [
            // Soft overlay tint for contrast & luxury readability
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/bones_pattern.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.15,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xBB030A14), Color(0xCC020610), Color(0xEE01040A)],
                  ),
                ),
              ),
            ),

            // Animated background floating elements (subtle gold/blue lines)
            AnimatedBuilder(
              animation: _bgController,
              builder: (context, child) {
                return Stack(
                  children: List.generate(10, (index) {
                    final offset =
                        (_bgController.value * MediaQuery.of(context).size.height) + (index * 80);
                    return Positioned(
                      top: offset % MediaQuery.of(context).size.height,
                      left: 0,
                      right: 0,
                      child: Container(height: 1, color: const Color(0xFFD9A441).withOpacity(0.03)),
                    );
                  }),
                );
              },
            ),

            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Box
                      _buildLogoSection(),

                      const SizedBox(height: 12),
                      // Texts
                      const Text(
                        'مساعد نخبة الأشعة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFD9A441),
                          shadows: [Shadow(color: Color(0x33D9A441), blurRadius: 10)],
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'جامعة النخبة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ELITE RADIOLOGY ASSISTANT',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9,
                          letterSpacing: 2.0,
                          color: Color(0xFFAAB7C8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '- AL NUKHBA UNIVERSITY -',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 8,
                          letterSpacing: 2.0,
                          color: Color(0xFFAAB7C8),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Form Card
                      _buildFormCard(),

                      const SizedBox(height: 32),

                      // Footer
                      const Text(
                        'تَصْمِيم الطَّالب : محمّد جَبَار إبراهيم',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD9A441),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• نرسم المستقبل بالأشعة والذكاء •',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Color(0xFFAAB7C8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF087CFF).withOpacity(0.15),
            blurRadius: 32,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Center(
        child: ClipOval(
          child: Image.asset(
            'assets/logo_icon_v2.png',
            width: 140,
            height: 140,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9A441).withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF087CFF).withOpacity(0.15),
            blurRadius: 40,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFFD9A441).withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF020814).withOpacity(0.85),
                  const Color(0xFF0A1224).withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                // Name Field
                _buildTextField(
                  controller: _nameController,
                  title: 'اسم المستخدم',
                  subtitle: 'يرجى كتابة الاسم الثلاثي',
                  icon: Icons.person_rounded,
                ),

                const SizedBox(height: 16),

                // Code Field
                _buildTextField(
                  controller: _codeController,
                  title: 'كود التفعيل',
                  subtitle: 'أدخل كود التفعيل المعتمد',
                  icon: Icons.lock_rounded,
                  isCode: true,
                ),

                const SizedBox(height: 18),

                // Registration / Subscription button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _openExternal(
                        Uri.parse('https://wa.me/9647721421419'),
                        'تعذر فتح WhatsApp',
                      );
                    },
                    icon: const Icon(Icons.school_rounded, color: Color(0xFF25D366)),
                    label: const Text(
                      'التسجيل والاشتراك 🎓',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Color(0xFFE2E8F0),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: const Color(0xFF25D366).withOpacity(0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF25D366).withOpacity(0.18)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'للحصول على كود الاشتراك وتفعيل حسابك، يرجى التواصل معنا عبر WhatsApp',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Color(0xFFE2E8F0),
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'WhatsApp 🌐: +964 772 142 1419',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Color(0xFF25D366),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        '⚠️ تنويه مهم:\n'
                        'الاشتراكات والأكواد حصرياً مخصصة لطلبة وأساتذة جامعة النخبة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Color(0xFFD9A441),
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                TextButton.icon(
                  onPressed: () => _openExternal(
                    Uri.parse('https://unrivaled-belekoy-e397c4.netlify.app/privacy-policy.html'),
                    'تعذر فتح سياسة الخصوصية حالياً',
                  ),
                  icon: const Icon(Icons.privacy_tip_outlined, size: 17),
                  label: const Text(
                    'بإرسال بيانات التفعيل، أقرّ أنني قرأت سياسة الخصوصية',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                  ),
                ),

                const SizedBox(height: 8),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleActivation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.transparent, // Background handled by container gradient
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFD9A441), width: 1),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0E1A33), Color(0xFF070F1C)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Color(0xFFD9A441),
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, color: Color(0xFFD9A441), size: 18),
                                  SizedBox(width: 12),
                                  Text(
                                    'إرسال وتفعيل',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: Color(0xFFE2E8F0),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String title,
    required String subtitle,
    required IconData icon,
    bool isCode = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFD9A441), size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Color(0xFFE2E8F0),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: isCode ? TextCapitalization.characters : TextCapitalization.words,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: subtitle,
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontFamily: 'Cairo'),
            filled: true,
            fillColor: const Color(0xFF0A1224).withOpacity(0.7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFD9A441), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFD9A441).withOpacity(0.3), width: 1),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFD9A441), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
