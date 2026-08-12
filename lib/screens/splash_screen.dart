import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/activation_provider.dart';
import 'chat_screen.dart';
import 'activation_screen.dart';
import 'safety_consent_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();

    // Setup background animation
    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat();

    // Setup Progress Bar Animation
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _progressController, curve: Curves.easeInOut));

    _progressController.forward();

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onProgressComplete();
      }
    });
  }

  void _onProgressComplete() {
    if (mounted) {
      _navigateToNext();
    }
  }

  Future<void> _navigateToNext() async {
    if (!mounted) return;
    final activationProvider = Provider.of<ActivationProvider>(context, listen: false);

    if (activationProvider.isLoading) {
      // If still loading providers, wait a bit more
      Future.delayed(const Duration(milliseconds: 500), _navigateToNext);
      return;
    }

    Widget nextScreen;
    if (!activationProvider.isActivated) {
      nextScreen = const ActivationScreen();
    } else if (await SafetyConsentScreen.hasAccepted()) {
      nextScreen = const ChatScreen();
    } else {
      nextScreen = const SafetyConsentScreen();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617), // Deep slate background
      body: Stack(
        children: [
          // Background animated grid/lines
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: List.generate(10, (index) {
                  return Positioned(
                    left:
                        (index * 40.0 + _bgController.value * 40.0) %
                        MediaQuery.of(context).size.width,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: const Color(0xFF38BDF8).withOpacity(0.03)),
                  );
                }),
              );
            },
          ),
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: List.generate(20, (index) {
                  return Positioned(
                    top:
                        (index * 40.0 + _bgController.value * 40.0) %
                        MediaQuery.of(context).size.height,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: const Color(0xFF38BDF8).withOpacity(0.03)),
                  );
                }),
              );
            },
          ),

          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Logo
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.3),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo_icon_v2.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.school, size: 70, color: Colors.blue),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Text: ELITERAD
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'ELITE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 8,
                        ),
                      ),
                      Text(
                        'RAD',
                        style: TextStyle(
                          color: const Color(0xFF38BDF8),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          shadows: [
                            Shadow(color: const Color(0xFF38BDF8).withOpacity(0.5), blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Text: RADIOLOGY AI
                  Text(
                    'RADIOLOGY AI',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      letterSpacing: 6,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Arabic Text
                  Text(
                    'مساعد نخبة الأشعة',
                    style: TextStyle(
                      color: const Color(0xFFC5A059),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      shadows: [
                        Shadow(color: const Color(0xFFC5A059).withOpacity(0.4), blurRadius: 10),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'ذكاء اصطناعي • تعليم أكاديمي • سلامة أولاً',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                      fontFamily: 'Cairo',
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Modality Icons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModalityIcon(Icons.accessibility_new, 'X-RAY'),
                      const SizedBox(width: 24),
                      _buildModalityIcon(Icons.album_outlined, 'CT'),
                      const SizedBox(width: 24),
                      _buildModalityIcon(Icons.view_in_ar, 'MRI'),
                      const SizedBox(width: 24),
                      _buildModalityIcon(Icons.wifi_tethering, 'ULTRASOUND'),
                    ],
                  ),

                  const Spacer(),

                  // Initialization Text
                  Text(
                    'SECURE INITIALIZATION',
                    style: TextStyle(
                      color: const Color(0xFF38BDF8),
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: const Color(0xFF38BDF8).withOpacity(0.5), blurRadius: 10),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Progress Bar
                  SizedBox(
                    width: 240,
                    height: 4,
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: _progressAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF38BDF8).withOpacity(0.8),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Percentage
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return Text(
                        '${(_progressAnimation.value * 100).toInt()}%',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Footer
                  Text(
                    'تَصْمِيمْ الطَّالِب: مُحَمَّد جَبَّار إِبْرَاهِيم',
                    style: TextStyle(
                      color: const Color(0xFFC5A059),
                      fontSize: 14,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalityIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 1.5),
            color: const Color(0xFF38BDF8).withOpacity(0.05),
          ),
          child: Icon(icon, color: const Color(0xFF38BDF8), size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, letterSpacing: 1),
        ),
      ],
    );
  }
}
