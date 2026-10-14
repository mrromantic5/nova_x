// lib/features/onboarding/models/onboarding_data.dart

import 'package:flutter/material.dart';

enum SlideHeroType { rive, image }

class OnboardingSlide {
  final SlideHeroType heroType;
  final String? assetPath;       // image path
  final String? riveAsset;       // rive file
  final String? riveAnimation;   // animation name to trigger
  final String headline;
  final String subheadline;
  final Color accentColor;
  final ShaderType shaderType;

  const OnboardingSlide({
    required this.heroType,
    this.assetPath,
    this.riveAsset,
    this.riveAnimation,
    required this.headline,
    required this.subheadline,
    required this.accentColor,
    this.shaderType = ShaderType.radial,
  });
}

enum ShaderType { radial, linearBottom, linearTop }

const List<OnboardingSlide> kOnboardingSlides = [
  OnboardingSlide(
    heroType:      SlideHeroType.rive,
    riveAsset:     'assets/bear.riv',
    riveAnimation: 'wave',
    headline:      'Welcome to NOVA X',
    subheadline:   'The future of browsing — faster, smarter,\nbuilt just for you.',
    accentColor:   Color(0xFF00D4FF),
    shaderType:    ShaderType.radial,
  ),
  OnboardingSlide(
    heroType:     SlideHeroType.image,
    assetPath:    'assets/images/slide2_speed.png',
    headline:     'Blazing Fast Browsing',
    subheadline:  'Rocket-speed page loads with smart\ntab management and instant search.',
    accentColor:  Color(0xFF00D4FF),
    shaderType:   ShaderType.linearBottom,
  ),
  OnboardingSlide(
    heroType:     SlideHeroType.image,
    assetPath:    'assets/images/slide3_privacy.png',
    headline:     'Privacy Shield On',
    subheadline:  'Block trackers, ads and threats before\nthey even reach your screen.',
    accentColor:  Color(0xFF7C3AED),
    shaderType:   ShaderType.radial,
  ),
  OnboardingSlide(
    heroType:     SlideHeroType.image,
    assetPath:    'assets/images/slide4_ai.png',
    headline:     'Meet Your AI Co-Pilot',
    subheadline:  'Ask anything, summarize pages\nand browse hands-free with Nova AI.',
    accentColor:  Color(0xFF00D4FF),
    shaderType:   ShaderType.radial,
  ),
  OnboardingSlide(
    heroType:     SlideHeroType.image,
    assetPath:    'assets/images/slide5_trust.png',
    headline:     'You\'re All Set!',
    subheadline:  'Join millions already browsing\nthe future with NOVA X.',
    accentColor:  Color(0xFF10B981),
    shaderType:   ShaderType.radial,
  ),
];
