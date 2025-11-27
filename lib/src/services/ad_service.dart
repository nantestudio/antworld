import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'analytics_service.dart';

/// Service for managing AdMob ads (banner, interstitial, rewarded)
class AdService {
  AdService._();
  static final instance = AdService._();

  // Test ad unit IDs - replace with real IDs before production
  static String get _bannerAdUnitId {
    if (kIsWeb) return '';
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/6300978111' // Android test
        : 'ca-app-pub-3940256099942544/2934735716'; // iOS test
  }

  static String get _interstitialAdUnitId {
    if (kIsWeb) return '';
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/1033173712' // Android test
        : 'ca-app-pub-3940256099942544/4411468910'; // iOS test
  }

  static String get _rewardedAdUnitId {
    if (kIsWeb) return '';
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/5224354917' // Android test
        : 'ca-app-pub-3940256099942544/1712485313'; // iOS test
  }

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  bool _isInitialized = false;
  bool _adsRemoved = false;
  int _gameStartCount = 0;

  /// Whether ads are available on this platform
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The currently loaded banner ad (null if not loaded)
  BannerAd? get bannerAd => _adsRemoved ? null : _bannerAd;

  /// Whether a rewarded ad is ready to show
  bool get isRewardedAdReady => !_adsRemoved && _rewardedAd != null;

  /// Initialize the ad SDK and request ATT on iOS
  Future<void> initialize() async {
    if (!isSupported || _isInitialized) return;

    // Request App Tracking Transparency on iOS
    if (Platform.isIOS) {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        // Wait a bit before showing ATT dialog (Apple requirement)
        await Future.delayed(const Duration(seconds: 1));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    }

    await MobileAds.instance.initialize();
    _isInitialized = true;

    // Preload ads
    _loadBannerAd();
    _loadInterstitialAd();
    _loadRewardedAd();
  }

  /// Load a banner ad
  void _loadBannerAd() {
    if (!isSupported || _adsRemoved) return;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Banner ad loaded');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
          _bannerAd = null;
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), _loadBannerAd);
        },
        onAdOpened: (ad) {
          AnalyticsService.instance.logAdEvent(adType: 'banner', event: 'click');
        },
      ),
    )..load();
  }

  /// Load an interstitial ad
  void _loadInterstitialAd() {
    if (!isSupported || _adsRemoved) return;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Interstitial ad loaded');
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial ad failed to load: ${error.message}');
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), _loadInterstitialAd);
        },
      ),
    );
  }

  /// Load a rewarded ad
  void _loadRewardedAd() {
    if (!isSupported || _adsRemoved) return;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Rewarded ad loaded');
          _rewardedAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad failed to load: ${error.message}');
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), _loadRewardedAd);
        },
      ),
    );
  }

  /// Called when user starts a new game - may show interstitial
  void onGameStart() {
    if (!isSupported || _adsRemoved) return;

    _gameStartCount++;
    // Show interstitial every 3rd game start
    if (_gameStartCount >= 3) {
      _gameStartCount = 0;
      showInterstitialAd();
    }
  }

  /// Show an interstitial ad if one is loaded
  Future<void> showInterstitialAd() async {
    if (!isSupported || _adsRemoved || _interstitialAd == null) return;

    AnalyticsService.instance.logAdEvent(adType: 'interstitial', event: 'show');
    await _interstitialAd!.show();
  }

  /// Show a rewarded ad and return whether user earned the reward
  Future<bool> showRewardedAd() async {
    if (!isSupported || _adsRemoved || _rewardedAd == null) return false;

    bool rewarded = false;

    AnalyticsService.instance.logAdEvent(adType: 'rewarded', event: 'show');

    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        rewarded = true;
        AnalyticsService.instance.logAdEvent(
          adType: 'rewarded',
          event: 'completed',
        );
      },
    );

    return rewarded;
  }

  /// Remove all ads (called after IAP purchase)
  void removeAds() {
    _adsRemoved = true;
    _bannerAd?.dispose();
    _bannerAd = null;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }

  /// Dispose all ads
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}
