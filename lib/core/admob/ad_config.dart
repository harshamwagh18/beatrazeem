import 'package:flutter/material.dart';

class AdMobConfig {
  static const bool enableBannerAds = true;
  static const bool enableRewardedAds = false;
  static const bool enableNativeAds = false;
  static const bool enableInterstitialAds = false;

  static const bool enableConsentManagement = false;

  static const String androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  static const String bannerAdUnitId = 'ca-app-pub-3940256099942544/9214589741';
  static const String rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const String nativeAdUnitId = 'ca-app-pub-3940256099942544/2247696110';
  static const String interstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';

  static const String testSetupNote =
      'Replace these test IDs with your real AdMob IDs before release.';

  static bool get isAnyAdEnabled =>
      enableBannerAds ||
      enableRewardedAds ||
      enableNativeAds ||
      enableInterstitialAds;
}
