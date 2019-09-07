//
//  ActivityIndicatorViewController.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//  Copyright © 2018 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import JGProgressHUD

public protocol ActivityIndicatorViewController: class {
    
    var view: UIView! { get }
    
    var navigationItem: UINavigationItem { get }
    
    var navigationController: UINavigationController? { get }
    
    var progressHUD: JGProgressHUD { get }
    
    func showProgressHUD()
    
    func dismissProgressHUD(animated: Bool)
}

public extension ActivityIndicatorViewController {
    
    func showProgressHUD() {
        
        self.view.isUserInteractionEnabled = false
        self.view.endEditing(true)
        
        //progressHUD.style = .currentStyle(for: self)
        progressHUD.interactionType = .blockTouchesOnHUDView
        progressHUD.show(in: self.navigationController?.view ?? self.view)
    }
    
    func dismissProgressHUD(animated: Bool = true) {
        
        self.view.isUserInteractionEnabled = true
        
        progressHUD.dismiss(animated: animated)
    }
}

public extension ActivityIndicatorViewController {
    
    func performActivity <T> (showProgressHUD: Bool = true,
                              queue: DispatchQueue? = nil,
                              _ asyncOperation: @escaping () throws -> T,
                              completion: ((Self, T) -> ())? = nil) {
        
        let queue = queue ?? appQueue
        
        if showProgressHUD { self.showProgressHUD() }
        
        queue.async {
            
            do {
                
                let value = try asyncOperation()
                
                mainQueue { [weak self] in
                    
                    guard let controller = self
                        else { return }
                    
                    if showProgressHUD { controller.dismissProgressHUD() }
                    
                    // success
                    completion?(controller, value)
                }
            }
                
            catch {
                
                mainQueue { [weak self] in
                    
                    guard let controller = self as? (UIViewController & ActivityIndicatorViewController)
                        else { return }
                    
                    if showProgressHUD { controller.dismissProgressHUD(animated: false) }
                    
                    // show error
                    log("⚠️ Error: \(error)")
                    controller.showErrorAlert(error.localizedDescription)
                }
            }
        }
    }
}
