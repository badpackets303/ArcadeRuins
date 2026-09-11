// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  TuningsViewController.swift
//  AudioKitSynthOne
//
//  Created by Marcus W. Hobbs on 5/30/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

class TuningsViewController: UIViewController {

    private var tableView: UITableView?

    public init(tableView: UITableView?) {

        self.tableView = tableView
        super.init(nibName: nil, bundle: nil)
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {

        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder aDecoder: NSCoder) {
        
        super.init(coder: aDecoder)
    }

    override func loadView() {

        if let tv = self.tableView {
            self.view = tv
        } else {
            self.view = UIView()
        }
    }
}
