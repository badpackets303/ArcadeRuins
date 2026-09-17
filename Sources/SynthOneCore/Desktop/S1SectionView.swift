//  A titled, textured section of the desktop layout (P6, ADR-045).
//
//  **New, not ported.** The classic panels are one storyboard scene each, drawn as a
//  flat grey field with labels placed by hand. The desktop layout groups the same
//  controls into sections: a header strip carrying the title and any header controls
//  (a filter-mode picker, an On switch), and a body in which the controls sit in a
//  horizontal stack. The gradient, border and shadow are the "texture" the owner asked
//  for on 2026-09-12. P7 (ADR-046): a skin may lay a pattern over the body and replace the
//  drop shadow with a glow in its accent.

import UIKit

final class S1SectionView: UIView {

    let titleLabel = UILabel()

    /// Controls that belong in the header strip, right-aligned.
    let headerAccessories = UIStackView()

    /// The section's controls. Horizontal, centred, spread across the width.
    let body = UIStackView()

    private let gradient = CAGradientLayer()
    private let bloom = CALayer()
    private let rim = CALayer()
    private let texture = UIView()

    /// P7-4 (ADR-048): the section's own neon, when the skin names one. Colours the border, the
    /// glow, the title's glow and the header's rule; every control inside finds it through
    /// `UIView.s1Accent`. Nil — Studio — leaves the palette's colours in place.
    var accent: UIColor? {
        didSet { applyAccent() }
    }

    private func applyAccent() {
        guard let accent else { return }
        let dress = S1Skins.current.dress
        defer {
            if dress.litFromAccent {
                for case let button as UIButton in headerAccessories.arrangedSubviews where button.layer.borderWidth > 0 {
                    button.layer.borderColor = accent.cgColor
                }
            }
        }
        if dress.bareSections { return }   // P7-9: the template has the frame and the title
        gradient.borderColor = accent.cgColor
        rim.borderColor = accent.mixed(with: .white, 0.45).withAlphaComponent(0.5).cgColor
        layer.shadowColor = accent.cgColor
        bloom.shadowColor = accent.cgColor
        header.setHairline(accent.withAlphaComponent(0.5))
        titleLabel.layer.shadowColor = accent.cgColor
        titleLabel.layer.shadowOpacity = 0.9
        titleLabel.layer.shadowRadius = 4
        titleLabel.layer.shadowOffset = .zero
    }
    private let header = S1GradientView(top: S1DesktopTheme.sectionHeaderTop,
                                        bottom: S1DesktopTheme.sectionHeaderBottom,
                                        hairline: S1DesktopTheme.hairline)

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let skin = S1Skins.current
        let dress = skin.dress
        gradient.colors = [S1DesktopTheme.sectionTop.cgColor, S1DesktopTheme.sectionBottom.cgColor]
        gradient.cornerRadius = S1DesktopTheme.sectionCornerRadius
        gradient.borderWidth = dress.sectionBorderWidth
        gradient.borderColor = S1DesktopTheme.sectionBorder.cgColor
        layer.insertSublayer(gradient, at: 0)
        if dress.sectionBloom, let glow = skin.sectionGlow {
            // P7-4: a wider, fainter glow under the sharp one
            bloom.shadowColor = glow.cgColor
            bloom.shadowOpacity = 0.3
            bloom.shadowRadius = 24
            bloom.shadowOffset = .zero
            layer.insertSublayer(bloom, at: 0)
        }
        if dress.sectionBorderWidth > 1 {
            // P7-4: a light inner rim, as a neon tube has
            rim.borderWidth = 1
            rim.cornerRadius = S1DesktopTheme.sectionCornerRadius - dress.sectionBorderWidth
            rim.borderColor = S1DesktopTheme.sectionBorder.mixed(with: .white, 0.45).withAlphaComponent(0.5).cgColor
            layer.insertSublayer(rim, above: gradient)
        }
        if let glow = skin.sectionGlow {
            layer.shadowColor = glow.cgColor
            layer.shadowOpacity = dress.sectionGlowOpacity
            layer.shadowRadius = dress.sectionGlowRadius
            layer.shadowOffset = .zero
        } else {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.55
            layer.shadowRadius = 3
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        if let pattern = skin.sectionTexture {
            texture.backgroundColor = UIColor(patternImage: pattern)
            texture.isUserInteractionEnabled = false
            texture.layer.cornerRadius = S1DesktopTheme.sectionCornerRadius
            texture.layer.masksToBounds = true
            texture.translatesAutoresizingMaskIntoConstraints = false
            addSubview(texture)
            NSLayoutConstraint.activate([
                texture.topAnchor.constraint(equalTo: topAnchor),
                texture.leadingAnchor.constraint(equalTo: leadingAnchor),
                texture.trailingAnchor.constraint(equalTo: trailingAnchor),
                texture.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        header.translatesAutoresizingMaskIntoConstraints = false
        header.layer.cornerRadius = S1DesktopTheme.sectionCornerRadius
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        header.layer.masksToBounds = true
        addSubview(header)

        titleLabel.text = title.uppercased()
        titleLabel.font = S1DesktopTheme.font(12, weight: .demiBold)
        titleLabel.textColor = S1DesktopTheme.text
        titleLabel.attributedText = NSAttributedString(string: title.uppercased(), attributes: [
            .kern: 1.2, .font: S1DesktopTheme.font(12, weight: .demiBold), .foregroundColor: S1DesktopTheme.text
        ])
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLabel)

        headerAccessories.axis = .horizontal
        headerAccessories.alignment = .center
        headerAccessories.spacing = 10
        headerAccessories.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerAccessories)

        if dress.bareSections {
            // P7-9 (ADR-059): the painting carries the frame, the strip and the title. The
            // label stays for VoiceOver and the tests; it is only not seen.
            for sublayer in [gradient, bloom, rim] { sublayer.isHidden = true }
            layer.shadowOpacity = 0
            texture.isHidden = true
            header.alpha = 1
            header.setColours(top: .clear, bottom: .clear)
            header.setHairline(.clear)
            titleLabel.alpha = 0
        }

        body.axis = .horizontal
        body.alignment = .center
        body.distribution = .equalCentering
        body.spacing = 8
        body.isLayoutMarginsRelativeArrangement = true
        body.layoutMargins = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: dress.sectionHeaderHeight),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            headerAccessories.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            headerAccessories.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerAccessories.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: S1DesktopTheme.sectionCornerRadius).cgPath
        if bloom.superlayer != nil {
            bloom.frame = bounds
            bloom.shadowPath = layer.shadowPath
        }
        if rim.superlayer != nil {
            let inset = gradient.borderWidth
            rim.frame = bounds.insetBy(dx: inset, dy: inset)
        }
        CATransaction.commit()
    }

    /// Adds a control to the body, wrapped in a cell that shows its name and value.
    @discardableResult
    func add(_ cell: UIView) -> UIView {
        body.addArrangedSubview(cell)
        return cell
    }

    func addHeaderAccessory(_ view: UIView) {
        headerAccessories.addArrangedSubview(view)
        applyAccent()
    }
}
