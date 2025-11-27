import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_service.dart';

/// A widget that displays a banner ad at the bottom of its container
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  @override
  Widget build(BuildContext context) {
    final adService = AdService.instance;

    // Don't show anything if ads aren't supported or no ad loaded
    if (!adService.isSupported || adService.bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: adService.bannerAd!.size.width.toDouble(),
      height: adService.bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: adService.bannerAd!),
    );
  }
}

/// A button that shows a rewarded ad when tapped
class RewardedAdButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRewarded;

  const RewardedAdButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onRewarded,
  });

  @override
  State<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends State<RewardedAdButton> {
  bool _isLoading = false;

  Future<void> _showRewardedAd() async {
    if (_isLoading) return;

    final adService = AdService.instance;
    if (!adService.isRewardedAdReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad not ready yet. Please try again.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final rewarded = await adService.showRewardedAd();

    if (mounted) {
      setState(() => _isLoading = false);

      if (rewarded) {
        widget.onRewarded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reward granted!'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final adService = AdService.instance;

    // Don't show if ads aren't supported
    if (!adService.isSupported) {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _showRewardedAd,
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon),
      label: Text(widget.label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black87,
      ),
    );
  }
}
