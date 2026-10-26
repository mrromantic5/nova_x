// lib/features/onboarding/models/onboarding_data.dart

import 'package:flutter/material.dart';

enum SlideHeroType { rive, image }
enum ShaderType { radial, linearBottom }

class OnboardingSlide {
  final SlideHeroType heroType;
  final String? assetPath;
  final String? riveAsset;
  final String? riveAnimation;
  final String headline;
  final String subheadline;
  final Color accentColor;

  const OnboardingSlide({
    required this.heroType,
    this.assetPath,
    this.riveAsset,
    this.riveAnimation,
    required this.headline,
    required this.subheadline,
    required this.accentColor,
  });
}

const List<OnboardingSlide> kOnboardingSlides = [
  // Slide 1 — Bear (Rive)
  OnboardingSlide(
    heroType:      SlideHeroType.rive,
    riveAsset:     'assets/bear.riv',
    riveAnimation: 'wave',
    headline:      'Welcome to NOVA X',
    subheadline:   'The future of browsing — faster, smarter,\nbuilt just for you.',
    accentColor:   Color(0xFF00D4FF),
  ),
  // Slide 2 — Rocket + browser
  OnboardingSlide(
    heroType:    SlideHeroType.image,
    assetPath:   'assets/images/slide2_speed.png',
    headline:    'Blazing Fast Browsing',
    subheadline: 'Rocket-speed page loads with smart\ntab management and instant search.',
    accentColor: Color(0xFF00D4FF),
  ),
  // Slide 3 — Shield + lock
  OnboardingSlide(
    heroType:    SlideHeroType.image,
    assetPath:   'assets/images/slide3_privacy.png',
    headline:    'Privacy Shield On',
    subheadline: 'Block trackers, ads and threats before\nthey even reach your screen.',
    accentColor: Color(0xFF7C3AED),
  ),
  // Slide 4 — AI robot  ← FIXED: capital S matches actual filename Slide4_ai.png
  OnboardingSlide(
    heroType:    SlideHeroType.image,
    assetPath:   'assets/images/Slide4_ai.png',
    headline:    'Meet Your AI Co-Pilot',
    subheadline: 'Ask anything, summarize pages\nand browse hands-free with Nova AI.',
    accentColor: Color(0xFF00D4FF),
  ),
  // Slide 5 — NOVA digital assistant (3.9.0).
  // Image: assets/images/slide_nova_assistant.png (1254×1254 PNG, dark
  // background like the other slides). Until it is added, a built-in NOVA
  // emblem is shown instead.
  OnboardingSlide(
    heroType:    SlideHeroType.image,
    assetPath:   'assets/images/slide_nova_assistant.png',
    headline:    'Say “Hey NOVA”',
    subheadline: 'Your digital assistant opens pages, plays\nmusic, tests your internet and answers — hands-free.',
    accentColor: Color(0xFF7C4DFF),
  ),
  // Slide 6 — Checkmark
  OnboardingSlide(
    heroType:    SlideHeroType.image,
    assetPath:   'assets/images/slide5_trust.png',
    headline:    'You\'re All Set!',
    subheadline: 'Join millions already browsing\nthe future with NOVA X.',
    accentColor: Color(0xFF10B981),
  ),
];
