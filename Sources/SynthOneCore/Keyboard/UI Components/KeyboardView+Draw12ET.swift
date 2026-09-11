// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  KeyboardView+Draw12ET.swift
//  AudioKitSynthOne
//
//  Created by Marcus W. Hobbs on 7/20/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

extension KeyboardView {

    // MARK: - Draw 12ET Keyboard

    internal func draw12ET(_ rect: CGRect) {

        updateOneOctaveSize()

        for i in 0 ..< octaveCount {
            drawOctaveCanvas(i)
        }
        let tempWidth = CGFloat(self.frame.width) - CGFloat((octaveCount * 7) - 1) * whiteKeySize.width - 1
        let backgroundPath = UIBezierPath(rect: CGRect(x: oneOctaveSize.width * CGFloat(octaveCount),
                                                       y: 0,
                                                       width: tempWidth,
                                                       height: oneOctaveSize.height))
        UIColor.black.setFill()
        backgroundPath.fill()
        let lastCRect = CGRect(x: whiteKeyX(0, octaveNumber: octaveCount),
                               y: 1,
                               width: tempWidth / 2,
                               height: whiteKeySize.height)
        let lastC = UIBezierPath(roundedRect: lastCRect, byRoundingCorners: [.bottomLeft, .bottomRight],
                                 cornerRadii: CGSize(width: 5, height: 5))
        whiteKeyColor(0, octaveNumber: octaveCount).setFill()
        lastC.fill()
        shadeWhiteKey(lastC, rect: lastCRect)   // PORT (ADR-035)
        addLabels(i: 0, octaveNumber: octaveCount, whiteKeysRect: lastCRect)
    }

    /// Update the screen size of one octave
    internal func updateOneOctaveSize() {

        let width = Int(self.frame.width)
        let height = Int(self.frame.height)
        oneOctaveSize = CGSize(width: Double(width / octaveCount - width / (octaveCount * octaveCount * 7)),
                               height: Double(height))
    }

    /// Draw one octave
    func drawOctaveCanvas(_ octaveNumber: Int) {

        //// background Drawing
        let backgroundPath = UIBezierPath(rect: CGRect(x: 0 + oneOctaveSize.width * CGFloat(octaveNumber),
                                                       y: 0,
                                                       width: oneOctaveSize.width,
                                                       height: oneOctaveSize.height))
        UIColor.black.setFill()
        backgroundPath.fill()
        var whiteKeysPaths = [UIBezierPath]()
        for i in 0 ..< 7 {
            let whiteKeysRect = CGRect(x: whiteKeyX(i, octaveNumber: octaveNumber),
                                       y: 1,
                                       width: whiteKeySize.width - 1,
                                       height: whiteKeySize.height)
            whiteKeysPaths.append(UIBezierPath(roundedRect: whiteKeysRect,
                                               byRoundingCorners: [.bottomLeft, .bottomRight],
                                               cornerRadii: CGSize(width: 5, height: 5)))
            whiteKeyColor(i, octaveNumber: octaveNumber).setFill()
            whiteKeysPaths[i].fill()
            shadeWhiteKey(whiteKeysPaths[i], rect: whiteKeysRect)   // PORT (ADR-035)
            addLabels(i: i, octaveNumber: octaveNumber, whiteKeysRect: whiteKeysRect)
        }

        // PORT (ADR-035): the black keys cast one soft shadow onto the white keys. They are
        // drawn as a single transparency layer, so the two overlapping slots that make up
        // each key cast one shadow rather than two.
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 2, height: 5), blur: 7,
                           color: UIColor(white: 0, alpha: 0.65).cgColor)
        context?.beginTransparencyLayer(auxiliaryInfo: nil)

        var topKeyPaths = [UIBezierPath]()
        for i in 0 ..< 28 {
            let topKeysRect = CGRect(x: topKeyX(i, octaveNumber: octaveNumber),
                                     y: 1,
                                     width: topKeySize.width + topKeyWidthIncrease,
                                     height: topKeySize.height)
            topKeyPaths.append(UIBezierPath(roundedRect: topKeysRect,
                                            byRoundingCorners: [.bottomLeft, .bottomRight],
                                            cornerRadii: CGSize(width: 3, height: 3)))
            topKeyColor(i, octaveNumber: octaveNumber).setFill()
            topKeyPaths[i].fill()

            // Add fancy paintcode blackkey code
        }

        context?.endTransparencyLayer()
        context?.restoreGState()
        shadeBlackKeys(octaveNumber)   // PORT (ADR-035)
    }

    /// Text
    func addLabels(i: Int, octaveNumber: Int, whiteKeysRect: CGRect) {

        let textColor: UIColor = darkMode.isDarkMode(view: self) ? #colorLiteral(red: 0.3176470588, green: 0.337254902, blue: 0.3647058824, alpha: 1) : #colorLiteral(red: 0.5098039216, green: 0.5098039216, blue: 0.5294117647, alpha: 1)

        // labelMode == 1, Only C, labelMode == 2, All notes
        if labelMode == 1 && i == 0 || labelMode == 2 {

            // Add Label
            guard let context = UIGraphicsGetCurrentContext(),
                let font = UIFont(name: "AvenirNextCondensed-Regular", size: 14) else { return }
            let whiteKeysTextContent = getWhiteNoteName(i) + String(firstOctave + octaveNumber)
            let whiteKeysStyle = NSMutableParagraphStyle()
            whiteKeysStyle.alignment = .center
            let whiteKeysFontAttributes  = [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: textColor,
                NSAttributedString.Key.paragraphStyle: whiteKeysStyle
                ] as [NSAttributedString.Key: Any]
            let whiteKeysTextHeight: CGFloat = whiteKeysTextContent.boundingRect(
                with: CGSize(width: whiteKeysRect.width,
                             height: CGFloat.infinity),
                options: .usesLineFragmentOrigin,
                attributes: whiteKeysFontAttributes,
                context: nil).height
            context.saveGState()
            context.clip(to: whiteKeysRect)

            // adjust for keyboard being hidden
            whiteKeysTextContent.draw(in: CGRect(x: whiteKeysRect.minX,
                                                 y: whiteKeysRect.minY + whiteKeysRect.height - whiteKeysTextHeight - 6,
                                                 width: whiteKeysRect.width,
                                                 height: whiteKeysTextHeight),
                                      withAttributes: whiteKeysFontAttributes)
            context.restoreGState()
        }
    }

    // MARK: - Shading (PORT, ADR-035)
    //
    // Upstream fills every key flat. On the Mac the keys are drawn at a size where that
    // reads as a diagram, so these paint depth over upstream's fills: a white key darkens
    // toward the back, where it runs under the black keys, and a black key lightens just
    // before its tip. Geometry, colours and hit-testing are unchanged.

    /// Darkens a white key toward the back.
    func shadeWhiteKey(_ path: UIBezierPath, rect: CGRect) {

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        path.addClip()
        context.drawLinearGradient(KeyboardShading.whiteKey,
                                   start: CGPoint(x: rect.midX, y: rect.minY),
                                   end: CGPoint(x: rect.midX, y: rect.maxY),
                                   options: [])
        context.restoreGState()
    }

    /// A lighter band before each black key's tip. A key is two or three overlapping
    /// slots in `topKeyNotes`, so the band is drawn once over their union.
    func shadeBlackKeys(_ octaveNumber: Int) {

        guard let context = UIGraphicsGetCurrentContext() else { return }
        var first = 0
        while first < topKeyNotes.count {
            let note = topKeyNotes[first]
            var last = first
            while last + 1 < topKeyNotes.count && topKeyNotes[last + 1] == note { last += 1 }
            if notesWithSharps[note].contains("#") {
                let minX = topKeyX(first, octaveNumber: octaveNumber)
                let maxX = topKeyX(last, octaveNumber: octaveNumber) + topKeySize.width + topKeyWidthIncrease
                let keyRect = CGRect(x: minX, y: 1, width: maxX - minX, height: topKeySize.height)
                context.saveGState()
                UIBezierPath(roundedRect: keyRect, byRoundingCorners: [.bottomLeft, .bottomRight],
                             cornerRadii: CGSize(width: 3, height: 3)).addClip()
                context.drawLinearGradient(KeyboardShading.blackKey,
                                           start: CGPoint(x: keyRect.midX, y: keyRect.minY),
                                           end: CGPoint(x: keyRect.midX, y: keyRect.maxY),
                                           options: [])
                context.restoreGState()
            }
            first = last + 1
        }
    }

    var whiteKeySize: CGSize {

        return CGSize(width: oneOctaveSize.width / 7.0, height: oneOctaveSize.height - 2)
    }

    var topKeySize: CGSize {

        return CGSize(width: oneOctaveSize.width / (4 * 7), height: oneOctaveSize.height * topKeyHeightRatio)
    }

    // swiftlint:disable identifier_name:min_length
    func whiteKeyX(_ n: Int, octaveNumber: Int) -> CGFloat {

        return CGFloat(n) * whiteKeySize.width + xOffset + oneOctaveSize.width * CGFloat(octaveNumber)
    }

    func topKeyX(_ n: Int, octaveNumber: Int) -> CGFloat {

        return CGFloat(n) * topKeySize.width - (topKeyWidthIncrease / 2) + xOffset +
            oneOctaveSize.width * CGFloat(octaveNumber)
    }

    func whiteKeyColor(_ n: Int, octaveNumber: Int) -> UIColor {

        let nn = MIDINoteNumber((firstOctave + octaveNumber) * 12 + whiteKeyNotes[n] + baseMIDINote )
        if darkMode.isDarkMode(view: self) {
            whiteKeyOff = #colorLiteral(red: 0.1333333333, green: 0.1333333333, blue: 0.1333333333, alpha: 1)
            keyOnColor = keyOnUserColor
        } else {
            whiteKeyOff = #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            keyOnColor = keyOnUserColor
        }

        return (onKeys.contains( nn ) || hostOnKeys.contains( nn )) ? keyOnColor : whiteKeyOff  // PORT (ADR-031)
    }

    func topKeyColor(_ n: Int, octaveNumber: Int) -> UIColor {

        let nn = MIDINoteNumber((firstOctave + octaveNumber) * 12 + topKeyNotes[n] + baseMIDINote )
        if darkMode.isDarkMode(view: self) {
            blackKeyOff = #colorLiteral(red: 0.2352941176, green: 0.2352941176, blue: 0.2549019608, alpha: 1)
            keyOnColor = keyOnUserColor
        } else {
            blackKeyOff = #colorLiteral(red: 0.09411764706, green: 0.09411764706, blue: 0.09411764706, alpha: 1)
            keyOnColor = keyOnUserColor
        }
        if notesWithSharps[topKeyNotes[n]].range(of: "#") != nil {
            return (onKeys.contains( nn ) || hostOnKeys.contains( nn )) ? keyOnColor : blackKeyOff  // PORT (ADR-031)
        }
        return #colorLiteral(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.000)
    }

    func getNoteName(_ note: Int) -> String {

        let keyInOctave = note % 12
        return notesWithSharps[keyInOctave]
    }

    func getWhiteNoteName(_ keyIndex: Int) -> String {

        return naturalNotes[keyIndex]
    }
}

/// PORT (ADR-035): the gradients the keyboard's shading paints with, built once.
private enum KeyboardShading {

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Stops as (location, white level, alpha).
    private static func gradient(_ stops: [(CGFloat, CGFloat, CGFloat)]) -> CGGradient {
        let colors = stops.map { CGColor(srgbRed: $0.1, green: $0.1, blue: $0.1, alpha: $0.2) }
        return CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: stops.map { $0.0 })!
    }

    /// Black, from 27% at the back of the key to nothing at the front.
    static let whiteKey = gradient([(0, 0, 0.27), (0.14, 0, 0.105), (0.6, 0, 0.015), (1, 0, 0)])

    /// White, only in the last fifth of the key: the front face of a raised key.
    static let blackKey = gradient([(0, 1, 0), (0.8, 1, 0), (0.86, 1, 0.1), (0.9, 1, 0.2), (1, 1, 0.1)])
}
