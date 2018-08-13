//
//  NearbyLocksViewController.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//  Copyright © 2018 ColemanCDA. All rights reserved.
//

import Foundation
import Bluetooth
import GATT
import CoreLock
    
#if os(iOS)
import UIKit
import CoreBluetooth
import DarwinGATT
import AVFoundation
import QRCodeReader
import JGProgressHUD
#endif

final class NearbyLocksViewController: UITableViewController {
    
    typealias Peripheral = NativeCentral.Peripheral
    
    // MARK: - Properties
    
    private var items = [LockPeripheral]() {
        
        didSet { configureView() }
    }
    
    let scanDuration: TimeInterval = 2.0
    
    #if os(iOS)
    
    internal lazy var progressHUD: JGProgressHUD = JGProgressHUD(style: .dark)
    
    private lazy var readerViewController: QRCodeReaderViewController = {
        
        let builder = QRCodeReaderViewControllerBuilder {
            $0.reader = QRCodeReader(metadataObjectTypes: [.qr], captureDevicePosition: .back)
        }
        
        return QRCodeReaderViewController(builder: builder)
    }()
    
    #endif
    
    // MARK: - Loading

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
        
        // try to scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: { [weak self] in self?.scan() })
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if items.isEmpty {
            
            scan()
        }
    }
    
    // MARK: - Actions
    
    @IBAction func scan(_ sender: Any? = nil) {
        
        self.refreshControl?.endRefreshing()
        
        /// ignore if off or not authorized
        #if os(iOS)
        guard LockManager.shared.central.state == .poweredOn
            else { return } // cannot scan
        #endif
        
        let scanDuration = self.scanDuration
        
        // reset table
        self.items.removeAll()
        
        // scan
        performActivity({ try Store.shared.scan(duration: scanDuration) },
                        completion: { (viewController, _) in viewController.configureView() })
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeripheralCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        let item = self[indexPath]
        
        select(item)
    }
    
    // MARK: - Private Methods
    
    private subscript (indexPath: IndexPath) -> LockPeripheral {
        
        return items[indexPath.row]
    }
    
    private func configureView() {
        
        self.items = Array(Store.shared.peripherals.values)
        
        tableView.reloadData()
    }
    
    private func configure(cell: UITableViewCell, at indexPath: IndexPath) {
        
        let lock = self[indexPath]
        
        let lockIdentifier = lock.information.identifier
        
        let title: String
        
        let isEnabled: Bool
        
        if let lockCache = Store.shared[lock: lockIdentifier] {
            
            title = lockCache.name
            isEnabled = true
            
        } else if lock.information.status == .setup {
            
            title = "Setup \(lockIdentifier)"
            isEnabled = true
            
        } else {
            
            title = lockIdentifier.description
            isEnabled = false
        }
        
        cell.textLabel?.text = title
        cell.selectionStyle = isEnabled ? .default : .none
    }
    
    private func select(_ lock: LockPeripheral) {
        
        log("Selected lock \(lock.information.identifier)")
        
        switch lock.information.status {
            
        case .setup:
            
            setup(lock)
            
        case .unlock:
            
            unlock(lock)
        }
    }
    
    private func unlock(_ lock: LockPeripheral) {
        
        
    }
    
    private func setup(_ lock: LockPeripheral) {
        
        // scan QR code
        assert(QRCodeReader.isAvailable())
        
        readerViewController.completionBlock = { [unowned self] (result: QRCodeReaderResult?) in
            
            // did not scan
            guard let result = result else { return }
            
            self.readerViewController.dismiss(animated: true, completion: {
                
                guard let data = Data(base64Encoded: result.value),
                    let sharedSecret = KeyData(data: data) else {
                    
                    self.showErrorAlert("Invalid QR code")
                    return
                }
                
                // perform BLE request
                self.setupLock(lock, sharedSecret: sharedSecret)
            })
        }
        
        // Presents the readerVC as modal form sheet
        readerViewController.modalPresentationStyle = .formSheet
        present(readerViewController, animated: true, completion: nil)
    }
    
    private func setupLock(_ lock: LockPeripheral, sharedSecret: KeyData, name: String = "Lock") {
        
        performActivity({ try Store.shared.setup(lock.peripheral, sharedSecret: sharedSecret, name: name) },
                        completion: { (viewController, _) in viewController.configureView() })
    }
}

// MARK: - ActivityIndicatorViewController

extension NearbyLocksViewController: ActivityIndicatorViewController { }
