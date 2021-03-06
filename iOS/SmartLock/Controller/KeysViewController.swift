//
//  KeysViewController.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 6/30/19.
//  Copyright © 2019 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import IntentsUI
import Bluetooth
import DarwinGATT
import GATT
import CoreLock
import LockKit
import JGProgressHUD
import OpenCombine
import CloudKit
import SFSafeSymbols

final class KeysViewController: UITableViewController {
    
    // MARK: - Properties
    
    public var showPendingKeys = true
    
    public lazy var activityIndicator: UIActivityIndicatorView = self.loadActivityIndicatorView()
    
    private var data = [Section]() {
        didSet { tableView.reloadData() }
    }
    
    private var pendingKeys = [URL: NewKey.Invitation]() {
        didSet { configureView() }
    }
    
    @available(iOS 13.0, *)
    private lazy var timeFormatter = RelativeDateTimeFormatter()
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    private var locksObserver: AnyCancellable?
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup table view
        tableView.register(LockTableViewCell.self)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        
        // load data
        locksObserver = Store.shared.locks.sink { locks in
            mainQueue { [weak self] in self?.configureView() }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        reloadData()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        userActivity = NSUserActivity(.screen(.keys))
        userActivity?.becomeCurrent()
        
        #if targetEnvironment(macCatalyst)
        syncCloud()
        #endif
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        hideActivity(animated: false)
    }
    
    // MARK: - Actions
    
    @IBAction func importFile(_ sender: UIBarButtonItem) {
                
        presentDocumentPicker(.barButtonItem(sender))
    }
    
    // MARK: - Actions
    
    @IBAction func refresh(_ sender: UIRefreshControl) {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reloadData()
        }
    }
    
    // MARK: - Methods
    
    private subscript (indexPath: IndexPath) -> Item {
        return data[indexPath.section].items[indexPath.row]
    }
    
    private func reloadData() {
        
        configureView()
        
        // load pending keys from CloudKit
        performActivity(queue: .app, {
            // load local files
            let pendingKeys = try Store.shared.fileManager.loadInvitations(invalid: { (url, error) in
                log("⚠️ Unable to load invitation from \(url.path). \(error.localizedDescription)")
            })
            mainQueue { [weak self] in
                self?.pendingKeys = pendingKeys
            }
            // fetch from CloudKit
            if (try? Store.shared.cloud.accountStatus()) == .available {
                do {
                    try Store.shared.fetchCloudNewKeys { (url, newKey) in
                        mainQueue { [weak self] in
                            self?.pendingKeys[url] = newKey
                        }
                    }
                }
                // ignore common errors
                catch CKError.networkUnavailable { }
                catch CKError.networkFailure { }
                catch CKError.requestRateLimited { }
            }
        })
    }
    
    private func configureView() {
        
        let applicationData = Store.shared.applicationData
        
        let showPendingKeys = self.showPendingKeys && pendingKeys.isEmpty == false
        
        let keys = applicationData.locks
            .lazy
            .sorted(by: { $0.value.key.created < $1.value.key.created })
            .map { Item.key($0, $1) }
        
        var data = [Section]()
        
        if showPendingKeys {
            let section = Section(
                title: R.string.keysViewController.pendingKeysTitle(),
                items: pendingKeys
                    .sorted(by: { $0.value.key.created < $1.value.key.created})
                    .map { .newKey($0, $1) }
            )
            data.append(section)
        }
        
        if keys.isEmpty == false {
            data.append(
                Section(
                    title: data.isEmpty ? nil : R.string.keysViewController.keysTitle(),
                    items: keys
                )
            )
        }
        
        self.data = data
    }
    
    private func configure(cell: LockTableViewCell, at indexPath: IndexPath) {
        
        let item = self[indexPath]
        
        let permission: Permission
        let name: String
        let detail: String
        
        switch item {
        case let .key(_, cache):
            permission = cache.key.permission
            name = cache.name
            detail = permission.localizedText
        case let .newKey(_, invitation):
            permission = invitation.key.permission
            name = invitation.key.name
            let expiration: String
            let timeRemaining = invitation.key.expiration.timeIntervalSinceNow
            if timeRemaining > 0 {
                if #available(iOS 13.0, *) {
                    let time = timeFormatter.localizedString(fromTimeInterval: timeRemaining)
                    expiration = R.string.keysViewController.expirationRelative(time) // "Expires \(time)"
                } else {
                    let date = dateFormatter.string(from: invitation.key.expiration)
                    expiration = R.string.keysViewController.expirationDate(date) // "Expires \(date)"
                }
            } else {
                expiration = R.string.keysViewController.expired() // "Expired"
            }
            detail = permission.localizedText + " - " + expiration
        }
        
        cell.lockTitleLabel.text = name
        cell.lockDetailLabel.text = detail
        cell.permissionView.permission = permission.type
        cell.activityIndicatorView.isHidden = true
        cell.permissionView.isHidden = false
    }
    
    private func select(_ item: Item) {
        
        switch item {
        case let .key(identifier, _):
            select(lock: identifier)
        case let .newKey(url, invitation):
            self.open(newKey: invitation) { [weak self] (didSave) in
                if didSave {
                    self?.delete(url)
                }
                self?.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    @discardableResult
    internal func select(lock identifier: UUID, animated: Bool = true) -> LockViewController? {
        
        guard Store.shared[lock: identifier] != nil else {
            showErrorAlert(LockError.noKey(lock: identifier).localizedDescription)
            return nil
        }
        
        let lockViewController = LockViewController.fromStoryboard(with: identifier)
        lockViewController.lockIdentifier = identifier
        if animated {
            self.show(lockViewController, sender: self)
        } else if let navigationController = self.navigationController {
            navigationController.pushViewController(lockViewController, animated: false)
        } else {
            assertionFailure()
        }
        return lockViewController
    }
    
    private func delete(_ url: URL) {
        
        DispatchQueue.app.async {
            do { try FileManager.default.removeItem(at: url) }
            catch {
                log("⚠️ Unable to delete \(url.lastPathComponent). \(error)")
                assertionFailure("Unable to delete \(url)")
            }
            mainQueue { [weak self] in
                self?.pendingKeys[url] = nil
            }
        }
    }
    
    private func delete(_ item: Item) {
        
        let alert = UIAlertController(title: R.string.keysViewController.alertTitle(),
                                      message: R.string.keysViewController.alertMessage(),
                                      preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: R.string.keysViewController.alertCancel(), style: .cancel, handler: { (UIAlertAction) in
            alert.dismiss(animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: R.string.keysViewController.alertDelete(), style: .destructive, handler: { [unowned self] (UIAlertAction) in
            
            switch item {
            case let .key(identifier, _):
                Store.shared.remove(identifier)
            case let .newKey(url, _):
                self.delete(url)
            }
            
            alert.dismiss(animated: true, completion: nil)
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    private func presentDocumentPicker(_ sender: PopoverPresentingView) {
        
        // temporarily set Appearence tint color
        UINavigationBar.appearance().tintColor = .systemBlue
        
        // show controller
        let documentPicker = UIDocumentPickerViewController(
            documentTypes: [NewKey.Invitation.documentType],
            in: .import
        )
        documentPicker.delegate = self
        self.present(documentPicker, sender: sender)
    }
    
    private func dismiss(_ controller: UIDocumentPickerViewController) {
        
        // restore Lock appearance
        UIView.configureLockAppearance()
        view.window?.setNeedsDisplay()
        
        // dismiss controller
        controller.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return data.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data[section].items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(LockTableViewCell.self, for: indexPath)
            else { fatalError("Could not dequeue reusable cell \(LockTableViewCell.self)") }
        configure(cell: cell, at: indexPath)
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        let item = self[indexPath]
        select(item)
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return data[section].title
    }
    
    #if !targetEnvironment(macCatalyst)
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        
        if #available(iOS 13.0, *) {
            return nil
        }
        
        var actions = [UITableViewRowAction]()
        let delete = UITableViewRowAction(style: .destructive, title: R.string.keysViewController.delete()) { [unowned self] in
            assert($1 == indexPath)
            let item = self[$1]
            self.delete(item)
        }
        
        actions.append(delete)
        return actions
    }
    #endif
    
    @available(iOS 13.0, *)
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        
        let item = self[indexPath]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] (menuElements) -> UIMenu? in
            
            switch item {
            case let .key(identifier, _):
                return self?.menu(forLock: identifier)
            case .newKey:
                let delete = UIAction(title: R.string.keysViewController.delete(), image: UIImage(systemSymbol: .trash), attributes: .destructive) { [weak self] (action) in
                    self?.delete(item)
                }
                return UIMenu(
                    title: "",
                    image: nil,
                    identifier: nil,
                    options: [],
                    children: [delete]
                )
            }
        }
    }
}

// MARK: - ActivityIndicatorViewController

extension KeysViewController: TableViewActivityIndicatorViewController { }

// MARK: - INUIAddVoiceShortcutViewControllerDelegate

@available(iOS 12, *)
extension KeysViewController: INUIAddVoiceShortcutViewControllerDelegate {
    
    public func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
        
        controller.dismiss(animated: true, completion: nil)
    }
    
    public func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}

// MARK: - UIDocumentPickerDelegate

extension KeysViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        dismiss(controller)
        
        // parse eKey file
        guard let url = urls.first,
            let data = try? Data(contentsOf: url),
            let newKey = try? JSONDecoder().decode(NewKey.Invitation.self, from: data) else {
                showErrorAlert(LockError.invalidNewKeyFile.localizedDescription)
                return
        }
        
        open(newKey: newKey)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        
        dismiss(controller)
        
        // parse eKey file
        guard let data = try? Data(contentsOf: url),
            let newKey = try? JSONDecoder().decode(NewKey.Invitation.self, from: data) else {
                showErrorAlert(LockError.invalidNewKeyFile.localizedDescription)
                return
        }
        
        open(newKey: newKey)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
        dismiss(controller)
    }
}

// MARK: - Supporting Types

private extension KeysViewController {
    
    struct Section {
        let title: String?
        let items: [Item]
    }
    
    enum Item {
        case key(UUID, LockCache)
        case newKey(URL, NewKey.Invitation)
    }
}
