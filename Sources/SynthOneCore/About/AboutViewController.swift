//
//  AboutViewController.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 3/28/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import UIKit
import MessageUI

protocol AboutDelegate: AnyObject {
    func showDevView()
}

class AboutViewController: UIViewController {
    
    @IBOutlet weak var parentView: UIView!
    @IBOutlet weak var textContainer: UIView!
    // PORT (ADR-040): upstream's `videoButton`, "How Synth One was made", is removed from
    // the storyboard at the owner's request, along with its outlet and callback.
    @IBOutlet weak var reviewButton: SynthButton!
    @IBOutlet weak var githubButton: SynthButton!
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var webButton: SynthButton!
    
    weak var delegate: AboutDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Hide popup at first
        parentView.alpha = 0
        textContainer.alpha = 0
        
        // Border of Popup
        textContainer.layer.borderColor = #colorLiteral(red: 0.09411764706, green: 0.09411764706, blue: 0.09411764706, alpha: 1)
        textContainer.layer.borderWidth = 2
        textContainer.layer.cornerRadius = 8
        
        setupCallbacks()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.mainTextView.setContentOffset(.zero, animated: false)
        
        // Fade in About Box
        UIView.animate(withDuration: 1, animations: {
            self.parentView.alpha = 1.0
        })
        
        UIView.animate(withDuration: 1.5, animations: {
            self.textContainer.alpha = 1.0
        })
    }
    
    func setupCallbacks() {
        
        githubButton.setValueCallback = { _ in
            self.githubButton.value = 0
            
            if Conductor.sharedInstance.device == .phone {
                self.emailSend()
            } else {
                if let url = URL(string: "https://github.com/AudioKit/") {
                    UIApplication.shared.open(url)
                }
            }
        }
        
        webButton.setValueCallback = { _ in
            self.webButton.value = 0
            if let url = URL(string: "https://github.com/badpackets303/ArcadeRuins") {
                UIApplication.shared.open(url)
            }
        }
        
        
        reviewButton.setValueCallback = { _ in
            self.reviewButton.value = 0
            // Not an App Store app (ADR-005), so there is no review to request —
            // `requestReview()` is StoreKit and does nothing outside the store.
            if let url = URL(string: "https://github.com/badpackets303/ArcadeRuins") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - IB Actions
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func closePressed(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func devViewPressed(_ sender: UIButton) {
        delegate?.showDevView()
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func emailPressed(_ sender: UIButton) {
        emailSend()
    }
    
    /// PORT: opens the issue tracker instead of composing mail to AudioKit.
    func emailSend() {
        if let url = URL(string: "https://github.com/badpackets303/ArcadeRuins/issues") {
            UIApplication.shared.open(url)
            return
        }
        let receipients: [String] = []
        let subject = "Arcade Ruins"
        let messageBody = ""
        
        let configuredMailComposeViewController = configureMailComposeViewController(recepients: receipients,
                                                                                     subject: subject,
                                                                                     messageBody: messageBody)
        
        if canSendMail() {
            self.present(configuredMailComposeViewController, animated: true, completion: nil)
        } else {
            showSendMailErrorAlert()
        }
    }
    
}

// MARK: - MFMailComposeViewController Delegate

extension AboutViewController: MFMailComposeViewControllerDelegate {
    
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    func canSendMail() -> Bool {
        return MFMailComposeViewController.canSendMail()
    }
    
    func configureMailComposeViewController(recepients: [String],
                                            subject: String,
                                            messageBody: String) -> MFMailComposeViewController {
        
        let mailComposerVC = MFMailComposeViewController()
        mailComposerVC.mailComposeDelegate = self
        
        mailComposerVC.setToRecipients(recepients)
        mailComposerVC.setSubject(subject)
        mailComposerVC.setMessageBody(messageBody, isHTML: false)
        
        return mailComposerVC
    }
    
    func showSendMailErrorAlert() {
        let sendMailErrorAlert = UIAlertController(title: "Could Not Send Email",
                                                   message: "Your device could not send e-mail.  " +
            "Please check e-mail configuration and try again.",
                                                   preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        
        sendMailErrorAlert.addAction(cancelAction)
        present(sendMailErrorAlert, animated: true, completion: nil)
    }
}
