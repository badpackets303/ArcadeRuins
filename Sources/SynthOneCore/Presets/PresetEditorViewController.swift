//
//  PresetEditorViewController.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 9/5/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import UIKit

protocol PresetPopOverDelegate: AnyObject {
    func didFinishEditing(name: String, category: Int, newBank: String)
}

class PresetEditorViewController: UIViewController {
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var categoryTableView: UITableView!
    @IBOutlet weak var popupView: UIView!
    // PORT FIX (ADR-033): was `bankPicker: UIPickerView!`. Under Optimize Interface for Mac a
    // UIPickerView throws as soon as it enters a window, so opening this editor crashed the app
    // and the plugin. A table in the picker's frame shows the same column of banks.
    @IBOutlet weak var bankTableView: UITableView!
    @IBOutlet weak var saveButton: SynthButton!
    @IBOutlet weak var cancelButton: SynthButton!

    weak var delegate: PresetPopOverDelegate?

    var preset = Preset()
    var categories = [""]
    let cellReuseIdentifier = "PopUpCell"
    let bankCellReuseIdentifier = "BankCell"   // PORT FIX (ADR-033)
    var categoryIndex = 0

    /// PORT FIX (ADR-033): three rows fill the picker's 80-point frame.
    var bankRowHeight: CGFloat { bankTableView.bounds.height / 3 }

    let conductor = Conductor.sharedInstance
    var pickerBankNames = [String]()
    var bankSelected = "BankA"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Register the table view cell class and its reuse id
        categoryTableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)

        popupView.layer.borderColor = #colorLiteral(red: 0.1333333333, green: 0.1333333333, blue: 0.1333333333, alpha: 1)
        popupView.layer.borderWidth = 4
        popupView.layer.cornerRadius = 6

        nameTextField.text = preset.name
        // PORT FIX (ADR-034): the storyboard gives this field a fixed near-white background and no
        // text colour, so in Dark appearance its text was the dynamic label colour — white on
        // #F8F8F8, unreadable. Pinned to Light, it draws as Interface Builder shows it in both.
        nameTextField.overrideUserInterfaceStyle = .light

        // Setup Picker
        //conductor.banks = conductor.banks.sorted { $0.position < $1.position }
        pickerBankNames = conductor.banks.map { $0.name }
        // PORT FIX (ADR-033): the picker is a table. A row of inset above and below lets the
        // first and last banks sit in the middle row, where the picker showed its selection.
        bankTableView.register(UITableViewCell.self, forCellReuseIdentifier: bankCellReuseIdentifier)
        bankTableView.contentInset = UIEdgeInsets(top: bankRowHeight, left: 0, bottom: bankRowHeight, right: 0)
        bankTableView.reloadData()
        bankTableView.layoutIfNeeded()
        if let index = pickerBankNames.firstIndex(of: preset.bank) {
            bankTableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .middle)
            bankSelected = preset.bank
        }
        
        // pull all preset categories
        categories.removeAll()
        for i in 0...PresetCategory.categoryCount {
            categories.append((PresetCategory(rawValue: i)?.description())!)
        }

        setupCallbacks()
		
		categoryTableView.accessibilityLabel = NSLocalizedString("Categories", comment: "Categories")
		categoryTableView.accessibilityHint = NSLocalizedString("Sets catagory for a preset.", comment: "Sets catagory for a preset.")
		
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        categoryTableView.reloadData()

        // Populate Preset current values
        categoryIndex = preset.category
        
        let indexPath = IndexPath(row: categoryIndex, section: 0)
        guard preset.category >= 0 && preset.category < PresetCategory.categoryCount else { return }
        categoryTableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
    }

    // MARK: - IBActions

    func setupCallbacks() {

        cancelButton.setValueCallback = { _ in
            self.dismiss(animated: true, completion: nil)
        }

        saveButton.setValueCallback = { _ in
            self.delegate?.didFinishEditing(name: self.nameTextField.text ?? "Unnamed",
                                            category: self.categoryIndex,
                                            newBank: self.bankSelected)
            self.dismiss(animated: true, completion: nil)
        }

    }

}

// MARK: - TableViewDataSource

extension PresetEditorViewController: UITableViewDataSource {

    func numberOfSections(in categoryTableView: UITableView) -> Int {
        return 1
    }

    @objc(tableView:heightForRowAtIndexPath:) func tableView(_ tableView: UITableView,
                                                             heightForRowAt indexPath: IndexPath) -> CGFloat {
        return tableView == bankTableView ? bankRowHeight : 44   // PORT FIX (ADR-033)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == bankTableView { return pickerBankNames.count }   // PORT FIX (ADR-033)
        if categories.isEmpty {
            return 1
        } else {
            return categories.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == bankTableView { return bankCell(at: indexPath) }   // PORT FIX (ADR-033)
        if let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier) as UITableViewCell? {
            cell.textLabel?.font = UIFont(name: "Avenir Next", size: 16)
            cell.textLabel?.text = categories[indexPath.row]
            return cell
        } else {
            let cell = UITableViewCell()
            cell.textLabel?.font = UIFont(name: "Avenir Next", size: 16)
            cell.textLabel?.text = categories[indexPath.row]
            return cell
        }
    }
}

// MARK: - TableViewDelegate

extension PresetEditorViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // PORT FIX (ADR-033): what the picker's didSelectRow did.
        if tableView == bankTableView { bankSelected = pickerBankNames[indexPath.row]; return }
        categoryIndex = (indexPath as NSIndexPath).row
    }

}

// MARK: - Bank table

// PORT FIX (ADR-033): replaces the UIPickerViewDataSource and UIPickerViewDelegate. Each row is
// the label the picker drew: same font, colour and alignment.
extension PresetEditorViewController {

    func bankCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = bankTableView.dequeueReusableCell(withIdentifier: bankCellReuseIdentifier, for: indexPath)
        cell.backgroundColor = .clear
        cell.textLabel?.font = UIFont(name: "Avenir Next Condensed", size: 18)
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.text = pickerBankNames[indexPath.row]
        cell.textLabel?.textColor = #colorLiteral(red: 0.7333333333, green: 0.7333333333, blue: 0.7333333333, alpha: 1)
        return cell
    }
}

// MARK: - UITextFieldDelegate

extension PresetEditorViewController: UITextFieldDelegate {
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        view.endEditing(true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        nameTextField.resignFirstResponder()
        return true
    }

}
