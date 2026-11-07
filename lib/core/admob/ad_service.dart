import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  BannerAd? _homeBannerAd;
  bool _isHomeBannerLoading = false;

  Future<void> initialize() async {
    if (!AdMobConfig.isAnyAdEnabled) {
      return;
    }

    try {
      await MobileAds.instance.initialize();
      if (AdMobConfig.enableConsentManagement) {
        await _requestConsentIfNeeded();
      }
    } catch (_) {
      // Ads are optional. The app should continue to function normally.
    }
  }

  Future<void> _requestConsentIfNeeded() async {
    try {
      final consentInfo = ConsentInformation.instance;
      await consentInfo.requestConsentInfoUpdate(ConsentRequestParameters());
    } catch (_) {
      // Consent failures must never block app startup.
    }
  }

  Future<void> preloadHomeBanner() async {
    if (!AdMobConfig.enableBannerAds || _isHomeBannerLoading || _homeBannerAd != null) {
      return;
    }

    _isHomeBannerLoading = true;

    try {
      final ad = BannerAd(
        adUnitId: AdMobConfig.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _homeBannerAd = ad as BannerAd;
            _isHomeBannerLoading = false;
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
            _isHomeBannerLoading = false;
          },
        ),
      );

      await ad.load();
    } catch (_) {
      _isHomeBannerLoading = false;
    }
  }

  Widget buildHomeBanner() {
    final ad = _homeBannerAd;
    if (!AdMobConfig.enableBannerAds || ad == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }

  Future<bool> showRewardedAdIfEnabled({required VoidCallback onReward}) async {
    if (!AdMobConfig.enableRewardedAds) {
      return false;
    }

    // Rewarded ads are intentionally disabled until a supported cosmetic flow exists.
    // This keeps core music sync and playback behavior untouched.
    onReward.call();
    return false;
  }

  Future<void> preloadInterstitialIfEnabled() async {
    if (!AdMobConfig.enableInterstitialAds) {
      return;
    }

    // Interstitials are intentionally disabled initially and must only be used in
    // safe session-ending states, never during active sync or playback.
  }

  Future<void> preloadNativeAdIfEnabled() async {
    if (!AdMobConfig.enableNativeAds) {
      return;
    }

    // Native ads are prepared but intentionally left disabled until a compatible
    // layout and labeling scheme are added.
  }

  void disposeHomeBanner() {
    _homeBannerAd?.dispose();
    _homeBannerAd = null;
    _isHomeBannerLoading = false;
  }
}
