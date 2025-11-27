import Foundation
import google_mobile_ads

/// A compact list-tile style native ad factory
class ListTileNativeAdFactory: FLTNativeAdFactory {
    func createNativeAd(
        _ nativeAd: GADNativeAd,
        customOptions: [AnyHashable : Any]? = nil
    ) -> GADNativeAdView? {

        // Create the native ad view
        let nativeAdView = GADNativeAdView()
        nativeAdView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)

        // Create headline label
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        headlineLabel.textColor = .white
        headlineLabel.numberOfLines = 1
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create body label
        let bodyLabel = UILabel()
        bodyLabel.text = nativeAd.body
        bodyLabel.font = UIFont.systemFont(ofSize: 12)
        bodyLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
        bodyLabel.numberOfLines = 1
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        // Create icon image view
        let iconView = UIImageView()
        iconView.image = nativeAd.icon?.image
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 4
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Create "Ad" badge
        let adBadge = UILabel()
        adBadge.text = "Ad"
        adBadge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        adBadge.textColor = .white
        adBadge.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1.0)
        adBadge.textAlignment = .center
        adBadge.layer.cornerRadius = 2
        adBadge.clipsToBounds = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        nativeAdView.addSubview(iconView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        nativeAdView.addSubview(adBadge)

        // Set constraints
        NSLayoutConstraint.activate([
            // Icon on left
            iconView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: nativeAdView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            // Ad badge top right of icon
            adBadge.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            adBadge.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 10),
            adBadge.widthAnchor.constraint(equalToConstant: 20),
            adBadge.heightAnchor.constraint(equalToConstant: 14),

            // Headline next to badge
            headlineLabel.leadingAnchor.constraint(equalTo: adBadge.trailingAnchor, constant: 6),
            headlineLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            headlineLabel.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 10),

            // Body below headline
            bodyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
        ])

        // Assign views to native ad view
        nativeAdView.headlineView = headlineLabel
        nativeAdView.bodyView = bodyLabel
        nativeAdView.iconView = iconView
        nativeAdView.nativeAd = nativeAd

        return nativeAdView
    }
}
