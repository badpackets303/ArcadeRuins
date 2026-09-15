//
//  PresetCell.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/28/16.
//  Copyright © 2016 AudioKit. All rights reserved.
//

import UIKit

protocol PresetCellDelegate: AnyObject {
    func editPressed()
    func duplicatePressed()
    func sharePressed()
    func favoritePressed()
}

class PresetCell: UITableViewCell {

    // MARK: - Properties / Outlets

    @IBOutlet weak var presetNameLabel: UILabel!
    @IBOutlet weak var renameButton: UIButton!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var duplicateButton: UIButton!
    @IBOutlet weak var favoriteButton: UIButton!
    @IBOutlet weak var labelTrailingConstraint: NSLayoutConstraint!
    
    weak var delegate: PresetCellDelegate?
    var currentPreset: Preset?
    let conductor = Conductor.sharedInstance

    // MARK: - Lifecycle

    /// PORT (P6-7): the desktop sidebar's rows are 30 points, not the storyboard's 44, and
    /// the label and buttons are placed by frame for 44 (the label at y 13), so they sat low in
    /// the highlighted row. Set by the desktop layout; the classic panel is unaffected.
    static var centresContentVertically = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard Self.centresContentVertically else { return }
        let midY = contentView.bounds.midY
        for view in contentView.subviews { view.center.y = midY }
        // PORT FIX (P8-0): the storyboard put the four buttons at x 324…487 of a 499-point cell
        // with a flexible right margin, so in the desktop browser's narrower rows only the star
        // was on screen and the rename, duplicate and share buttons — and with them the preset
        // editor — were off the right edge (owner, 2026-09-13: "Where did the preset editor
        // go?"). Keep their order, from the trailing edge; the name takes what is left.
        var x = contentView.bounds.width - 8
        for button in [shareButton, duplicateButton, renameButton, favoriteButton] as [UIButton] {
            x -= button.bounds.width
            button.frame.origin.x = x
            x -= 4
        }
        let visible = ([shareButton, duplicateButton, renameButton, favoriteButton] as [UIButton]).filter { !$0.isHidden }
        let limit = (visible.map { $0.frame.minX }.min() ?? contentView.bounds.width) - 6
        presetNameLabel.frame.size.width = max(40, limit - presetNameLabel.frame.minX)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code

        // set cell selection color
        let selectedView = UIView(frame: CGRect.zero)
        selectedView.backgroundColor = UIColor.clear
        selectedBackgroundView = selectedView
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        let color = duplicateButton.backgroundColor
        super.setSelected(selected, animated: animated)
        if Self.centresContentVertically { setNeedsLayout() }   // PORT (P8-0): the buttons' room changes

        duplicateButton.backgroundColor = color
        renameButton.backgroundColor = color
        shareButton.backgroundColor = color

        // Configure the view for the selected state
        if selected {
            labelTrailingConstraint?.constant = 132
            presetNameLabel.textColor = UIColor.white
            backgroundColor = #colorLiteral(red: 0.2431372549, green: 0.2431372549, blue: 0.262745098, alpha: 1)

            duplicateButton.isHidden = false
            renameButton.isHidden = false
            shareButton.isHidden = false
            favoriteButton.isHidden = false

        } else {
            labelTrailingConstraint?.constant = 5
            presetNameLabel.textColor = #colorLiteral(red: 0.7333333333, green: 0.7333333333, blue: 0.7333333333, alpha: 1)
            backgroundColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 0)

            duplicateButton.isHidden = true
            renameButton.isHidden = true
            shareButton.isHidden = true
            favoriteButton.isHidden = true
        }
    }

    func configureCell(preset: Preset, alpha: Bool) {
        currentPreset = preset

        guard let bank = conductor.banks.first(where: { $0.name == preset.bank }) else { return }
        
        if conductor.device == .phone {
            presetNameLabel.font = UIFont(name: "Avenir Next", size: 14)
        }
        
        if alpha {
            presetNameLabel.text = "\(preset.name) (Bank \(bank.position) ‣ \(preset.position))"
        } else {
            if preset.bank != "BankA" {
                presetNameLabel.text = "[\(bank.position)] ‣ \(preset.position): \(preset.name)"
            } else {
                presetNameLabel.text = "\(preset.position): \(preset.name)"
            }
        }

        if preset.isFavorite {
            favoriteButton.setImage(UIImage.synthOne("ak_favfilled")!, for: .normal)
        } else {
            favoriteButton.setImage(UIImage.synthOne("ak_fav")!, for: .normal)
        }

    }

    @IBAction func duplicatePressed(_ sender: UIButton) {
        delegate?.duplicatePressed()
    }

    @IBAction func editPressed(_ sender: UIButton) {
        delegate?.editPressed()
    }

    @IBAction func sharePressed(_ sender: UIButton) {
        delegate?.sharePressed()
    }

    @IBAction func favoritePressed(_ sender: UIButton) {
        delegate?.favoritePressed()
    }
}
