//
//  TutorialManager.swift
//  PBTutorialManager
//
//  Created by Paul Bancarel on 05/07/2016.
//  Copyright © 2016 TheFrenchTouchDeveloper. All rights reserved.
//

import Foundation
import AFCurvedArrowView


open class TutorialManager: NSObject {
    private      var targets:             [TutorialTarget] = [] // The targets to work with
    private weak var parent:              UIView!               // The window/view represents which contains all the targets
    private weak var mask:                HoledView?
    private      var timeOutCount         = 0
    private      var fadeInDelay:         TimeInterval?
    private      var tutorialComplete:    (() -> Void)?
    private      var removableConstraints = [NSLayoutConstraint]()
    private      var absConstraints       = [NSLayoutConstraint]()
    private      var targetConstraints    = [(constraint: NSLayoutConstraint, originalConstant: CGFloat)]()
    private      let constraintPri        = UILayoutPriority(500) // lower than normal so we can't conflict with the main GUI
    
    public init(parent: UIView, fadeInDelay: TimeInterval? = nil, tutorialComplete: (() -> Void)? = nil) {
        self.fadeInDelay      = fadeInDelay
        self.parent           = parent
        self.tutorialComplete = tutorialComplete
        super.init()
    }
    
    /**
     Add a target
     
     - Parameters:
     - target: The target to add
     */
    open func addTarget(_ target: TutorialTarget) {
        targets.append(target)
    }
    
    open func addTargets(_ targets: [TutorialTarget]) {
        self.targets.append(contentsOf: targets)
    }
    
    open func cancelTutorial() {
        removeUiItems()
        targets.removeAll()
        tutorialComplete?()
    }
    
    private func removeUiItems() {
        mask?.removeFromSuperview()
        mask = nil
        parent.removeConstraints(removableConstraints)
        parent.removeConstraints(absConstraints)
        removableConstraints.removeAll()
        absConstraints.removeAll()
        targetConstraints.removeAll()
    }
    
    func updateConstraints(holes: [Hole]) {
        parent.removeConstraints(absConstraints)
        absConstraints.removeAll()
        for hole in holes {
            addAbsConstraints(hole: hole)
        }
    }

    public func refreshConstraints() {
        if let mask {
            mask.setNeedsUpdateConstraints()
            mask.updateConstraintsIfNeeded()
            restoreConstraints()
            refreshArrowConstraints()
            mask.setNeedsDisplay()
        }
    }

    private func refreshArrowConstraints() {
        if let parent {
            // Floating toolbars can move their hosting view without updating the cross-hierarchy
            // Auto Layout position of a custom button. Keep the arrow constrained to that button,
            // correcting the constant from their actual positions after the transition.
            parent.layoutIfNeeded()
            var corrected = false
            for (constraint, originalConstant) in targetConstraints where constraint.isActive {
                if let arrow  = constraint.firstItem  as? UIView,
                   let target = constraint.secondItem as? UIView,
                   !arrow.isHidden,
                   arrow.isDescendant(of:  parent),
                   target.isDescendant(of: parent),
                   !arrow.bounds.isEmpty, !target.bounds.isEmpty,
                   let arrowAnchor  = anchor(constraint.firstAttribute,  in: arrow.convert(arrow.bounds, to: parent)),
                   let targetAnchor = anchor(constraint.secondAttribute, in: target.convert(target.bounds, to: parent)) {
                    let correction = targetAnchor + originalConstant - arrowAnchor
                    if abs(correction) > 0.5 {
                        constraint.constant += correction
                        corrected = true
                    }
                }
            }
            if corrected {
                parent.layoutIfNeeded()
            }
        }
    }

    private func anchor(_ attribute: NSLayoutConstraint.Attribute, in rect: CGRect) -> CGFloat? {
        return switch attribute {
        case .left, .leading:   rect.minX
        case .right, .trailing: rect.maxX
        case .centerX:          rect.midX
        case .top:              rect.minY
        case .bottom:           rect.maxY
        case .centerY:          rect.midY
        default:                nil
        }
    }

    func restoreConstraints() {
        for constraint in removableConstraints where !constraint.isActive {
            let views = [constraint.firstItem, constraint.secondItem].compactMap({ $0 as? UIView })
            if views.allSatisfy({ $0.isDescendant(of: parent) }) {
                constraint.isActive = true
            }
        }
    }
    
    /**
     Fire the targets, when you have finished to set-up and add all your targets
     */
    open func fireTargets() {
        guard parent != nil else {
            tutorialComplete?()
            return
        }
        
        // Under some rare corner cases a the view target may not be visible when the tutorial is
        // fired, even if the tutorial is started from viewDidAppear(). One case where this is known
        // to happen is for buttons on a tool bar in the detail view of a splitViewController. For
        // some strange reason these buttons visibly appear about 0.5 seconds after the rest of the
        // view controller if the master view also has a tool bar.
        if let currentTarget = targets.first {
            if currentTarget.view?.window != nil {
                timeOutCount = 0
                currentTarget.onShow?()
                showTarget(currentTarget)
            } else if timeOutCount < 20 {
                // The items target view isn't visible yet so we can't show the tutorial for it, as
                // this would create constraints to a view that isn't in the hierarchy and cause a
                // crash. Instead a retry is scheduled for 100ms in the future. This delay is a
                // compromise between keeping the UI responcive and not retrying to often and using
                // lots of CPU time. The retry limit of 20 above produces an overall timeout of 2
                // seconds. This is another compromise between being significantly larger than the
                // usual delay we see in the view being added to the hierarchy (0.5 seconds), and
                // being short enough that app won't have appeared to lockup. In theory the timeout
                // will never actually be reached, but it's safer to have a fallback path just in
                // case.
                timeOutCount += 1
                let deadline  = DispatchTime.now() + 0.1
                DispatchQueue.main.asyncAfter(deadline: deadline, execute: fireTargets)
            } else {
                // Timeout for this target reached, so skip it and try and next. In theory this
                // should never happen, but we need it a a fall back to prevent lockups if something
                // strange happens.
                timeOutCount = 0
                targets.removeFirst()
                fireTargets()
            }
        } else {
            tutorialComplete?()
        }
    }
    
    /**
     Called repeteadly for each target in targets
     
     - Parameters:
     - target: The target to show
     - onView: viewToDrawIn
     */
    fileprivate func showTarget(_ target: TutorialTarget) {
        let mask: HoledView
        
        /* Should we create a new mask or not */
        if let classMask = self.mask {
            // Reuse mask
            mask = classMask
        } else {
            // New mask and add it to the parentView
            mask             = HoledView(frame: parent.frame, manager: self)
            self.mask        = mask
            mask.tapListener = tapped
            parent.addSubview(mask)
            
            // Fade in the holed view. Only fade in on the first display
            if let delay = fadeInDelay {
                fadeInDelay = nil
                mask.alpha  = 0
                UIView.animate(withDuration: delay) {
                    mask.alpha = 1
                }
            }
            
            // Fit the size of the mask to the size of the screen
            mask.translatesAutoresizingMaskIntoConstraints = false
            parent.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[mask]|", options: [.alignAllCenterX, .alignAllCenterY], metrics: nil, views: ["mask":mask])) //Equal Width
            parent.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[mask]|", options: [.alignAllCenterX, .alignAllCenterY], metrics: nil, views: ["mask":mask])) //Equal Height
        }
        
        /* Position the target on the view */
        if let view = target.view {
            // Check the type of the target
            var hole: Hole? = nil
            switch target.shape {
            case .elipse?:
                hole = mask.addElipse(view: view)
            case .rect?:
                hole = mask.addRectHole(view: view)
            case .roundedRect?:
                hole = mask.addRectHole(view: view, cornerRadius: 10)
            default:
                ()
            }
            
            // Get the properties of the target
            let label = UILabel()
            let arrow = target.position != .centre ? AFCurvedArrowView() : nil
            let arrowHeadX: NSLayoutConstraint.Attribute
            let arrowHeadY: NSLayoutConstraint.Attribute
            var constraints = [NSLayoutConstraint]()
            var targetConstraints = [NSLayoutConstraint]()
        
            // Now setup the arrow direction
            if let arrow = arrow {
                switch target.arrowStartPosition ?? target.position {
                case .top:
                    arrow.arrowTail = CGPoint(x: 0.5, y: 0.05)
                    arrow.arrowHead = CGPoint(x: 0.5, y: 0.95)
                    arrow.controlPoint1 = CGPoint(x: 0.8, y: 0.4)
                    arrow.controlPoint2 = CGPoint(x: 0.2, y: 0.6)
                    arrowHeadX = .centerX
                    arrowHeadY = .bottom
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .centerX, relatedBy: .equal,
                                                          toItem: arrow, attribute: .centerX, multiplier: 1, constant: target.leftTextMargin - target.rightTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .bottom,  relatedBy: .equal,
                                                          toItem: arrow, attribute: .top,     multiplier: 1, constant: target.bottomTextMargin))
                    
                case .bottom:
                    arrow.arrowTail = CGPoint(x: 0.5, y: 0.95)
                    arrow.arrowHead = CGPoint(x: 0.5, y: 0.05)
                    arrow.controlPoint1 = CGPoint(x: 0.2, y: 0.6)
                    arrow.controlPoint2 = CGPoint(x: 0.8, y: 0.4)
                    arrowHeadX = .centerX
                    arrowHeadY = .top
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .centerX, relatedBy: .equal,
                                                          toItem: arrow, attribute: .centerX, multiplier: 1, constant: target.leftTextMargin - target.rightTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .top,     relatedBy: .equal,
                                                          toItem: arrow, attribute: .bottom,  multiplier: 1, constant: target.topTextMargin))
                    
                case .left:
                    arrow.arrowTail = CGPoint(x: 0.05, y: 0.5)
                    arrow.arrowHead = CGPoint(x: 0.95, y: 0.5)
                    arrow.controlPoint1 = CGPoint(x: 0.5, y: 1.0)
                    arrowHeadX = .right
                    arrowHeadY = .centerY
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .right,   relatedBy: .equal,
                                                          toItem: arrow, attribute: .left,    multiplier: 1, constant: target.rightTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .centerY, relatedBy: .equal,
                                                          toItem: arrow, attribute: .centerY, multiplier: 1, constant: target.topTextMargin - target.bottomTextMargin))
                    
                case .right:
                    arrow.arrowTail = CGPoint(x: 0.95, y: 0.5)
                    arrow.arrowHead = CGPoint(x: 0.05, y: 0.5)
                    arrow.controlPoint1 = CGPoint(x: 0.5, y: 0.0)
                    arrowHeadX = .left
                    arrowHeadY = .centerY
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .left,    relatedBy: .equal,
                                                          toItem: arrow, attribute: .right,   multiplier: 1, constant: target.leftTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .centerY, relatedBy: .equal,
                                                          toItem: arrow, attribute: .centerY, multiplier: 1, constant: target.topTextMargin - target.bottomTextMargin))
                    
                case .topLeft:
                    arrow.arrowTail = CGPoint(x: 0.05, y: 0.05)
                    arrow.arrowHead = CGPoint(x: 0.95, y: 0.95)
                    arrow.controlPoint1 = CGPoint(x: 0.8, y: 0.2)
                    arrowHeadX = .right
                    arrowHeadY = .bottom
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .right,  relatedBy: .equal,
                                                          toItem: arrow, attribute: .left,   multiplier: 1, constant: target.rightTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .bottom, relatedBy: .equal,
                                                          toItem: arrow, attribute: .top,    multiplier: 1, constant: target.bottomTextMargin))
                    
                case .topRight:
                    arrow.arrowTail = CGPoint(x: 0.95, y: 0.05)
                    arrow.arrowHead = CGPoint(x: 0.05, y: 0.95)
                    arrow.controlPoint1 = CGPoint(x: 0.2, y: 0.2)
                    arrowHeadX = .left
                    arrowHeadY = .bottom
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .left,   relatedBy: .equal,
                                                          toItem: arrow, attribute: .right,  multiplier: 1, constant: target.leftTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .bottom, relatedBy: .equal,
                                                          toItem: arrow, attribute: .top,    multiplier: 1, constant: target.bottomTextMargin))
                    
                case .bottomLeft:
                    arrow.arrowTail = CGPoint(x: 0.05, y: 0.95)
                    arrow.arrowHead = CGPoint(x: 0.95, y: 0.05)
                    arrow.controlPoint1 = CGPoint(x: 0.8, y: 0.8)
                    arrowHeadX = .right
                    arrowHeadY = .top
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .right,  relatedBy: .equal,
                                                          toItem: arrow, attribute: .left,   multiplier: 1, constant: target.leftTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .top,    relatedBy: .equal,
                                                          toItem: arrow, attribute: .bottom, multiplier: 1, constant: target.topTextMargin))
                    
                case .bottomRight:
                    arrow.arrowTail = CGPoint(x: 0.95, y: 0.95)
                    arrow.arrowHead = CGPoint(x: 0.05, y: 0.05)
                    arrow.controlPoint1 = CGPoint(x: 0.2, y: 0.8)
                    arrowHeadX = .left
                    arrowHeadY = .top
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .left,   relatedBy: .equal,
                                                          toItem: arrow, attribute: .right,  multiplier: 1, constant: target.leftTextMargin))
                    constraints.append(NSLayoutConstraint(item: label,   attribute: .top,    relatedBy: .equal,
                                                          toItem: arrow, attribute: .bottom, multiplier: 1, constant: target.topTextMargin))
                    
                case .centre:
                    assertionFailure("Centre possition isn't valid for the arrow start point")
                    arrowHeadX = .notAnAttribute
                    arrowHeadY = .notAnAttribute
                }
            } else {
                arrowHeadX = .notAnAttribute
                arrowHeadY = .notAnAttribute
            }
            
            switch target.position {
            case .top:
                /* Illustration
                 H:[view]-[arrowView]-[label]
                 V:[view]-topMargin-[arrowView]-bottomTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .centerX,   multiplier: 1, constant: target.leftMargin - target.rightMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .top,       multiplier: 1, constant: target.topMargin))
                
            case .bottom:
                /* Illustration
                 H:[view]-[arrowView]-[label]
                 V:[view]-bottomMargin-[arrowView]-topTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .centerX,   multiplier: 1, constant: target.leftMargin - target.rightMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .bottom,    multiplier: 1, constant: target.bottomMargin))
                
            case .left:
                /* Illustration
                 H:[label]-rightTextMargin-[arrowView]-leftMargin-[view]
                 V:[label]-[arrowView]-[view] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .left,      multiplier: 1, constant: target.leftMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .centerY,   multiplier: 1, constant: target.topMargin - target.bottomMargin))
                
            case .right:
                /* Illustration
                 H:[view]-rightMargin-[arrowView]-leftTextMargin-[label]
                 V:[view]-[arrowView]-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .right,     multiplier: 1, constant: target.rightMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .centerY,   multiplier: 1, constant: target.topMargin - target.bottomMargin))
                
            case .topLeft:
                /* Illustration
                 H:[label]-rightTextMargin-[arrowView]-leftMargin-[view]
                 V:[view]-topMargin-[arrowView]-bottomTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .left,      multiplier: 1, constant: target.leftMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .top,       multiplier: 1, constant: target.topMargin))
                
            case .topRight:
                /* Illustration
                 H:[view]-rightMargin-[arrowView]-leftTextMargin-[label]
                 V:[view]-topMargin-[arrowView]-bottomTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .right,     multiplier: 1, constant: target.rightMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .top,       multiplier: 1, constant: target.topMargin))
                
            case .bottomLeft:
                /* Illustration
                 H:[label]-rightTextMargin-[arrowView]-leftMargin-[view]
                 V:[view]-bottomMargin-[arrowView]-topTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .left,      multiplier: 1, constant: target.leftMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .bottom,    multiplier: 1, constant: target.bottomMargin))
                
            case .bottomRight:
                /* Illustration
                 H:[view]-rightMargin-[arrowView]-leftTextMargin-[label]
                 V:[view]-bottomMargin-[arrowView]-topTextMargin-[label] */
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadX, relatedBy: .equal,
                                                            toItem: view, attribute: .right,     multiplier: 1, constant: target.rightMargin))
                targetConstraints.append(NSLayoutConstraint(item: arrow!, attribute: arrowHeadY, relatedBy: .equal,
                                                            toItem: view, attribute: .bottom,    multiplier: 1, constant: target.bottomMargin))
                
            case .centre:
                constraints.append(NSLayoutConstraint(item: label,    attribute: .centerX, relatedBy: .equal,
                                                      toItem: view,   attribute: .centerX, multiplier: 1, constant: target.leftTextMargin - target.rightTextMargin))
                constraints.append(NSLayoutConstraint(item: label,    attribute: .centerY, relatedBy: .equal,
                                                      toItem: view,   attribute: .centerY, multiplier: 1, constant: target.topTextMargin - target.bottomTextMargin))
            }
            
            for constraint in targetConstraints {
                constraints.append(constraint)
                self.targetConstraints.append((constraint: constraint, originalConstant: constraint.constant))
            }
            
            // Setup the label attributes
            label.numberOfLines = 0
            label.textColor = UIColor.white
            label.font = target.font
            label.text = target.message
            label.textAlignment = target.textAlignement
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            // Weaken the width compression resistance so it is below the priority of the
            // possitioning constraints of UIButtonBarItem's. Otherwise the tutorial labels can
            // cause the items to move.
            label.setContentCompressionResistancePriority(UILayoutPriority(rawValue: constraintPri.rawValue - 1), for: .horizontal)
            // Add a max width constraint to the label. We leave the height unconstrained so it can
            // expand to fit the text as required
            constraints.append(NSLayoutConstraint(item: label, attribute: .width,          relatedBy:  .lessThanOrEqual,
                                                  toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: target.labelWidth))
            // Now make sure the label doesn't go outside the parent
            constraints.append(NSLayoutConstraint(item: label,     attribute: .leading,  relatedBy:  .greaterThanOrEqual,
                                                   toItem: parent, attribute: .leading,  multiplier: 1, constant: 0))
            constraints.append(NSLayoutConstraint(item: parent!,   attribute: .trailing, relatedBy:  .greaterThanOrEqual,
                                                  toItem: label,   attribute: .trailing, multiplier: 1, constant: 0))

            // Add an arrow if the user as ask for one
            if target.withArrow, let arrowView = arrow {
                arrowView.arrowHeadHeight = target.arrowHeadSize
                arrowView.arrowHeadWidth = target.arrowHeadSize
                arrowView.curveType = .quadratic
                arrowView.translatesAutoresizingMaskIntoConstraints = false
                constraints.append(NSLayoutConstraint(item: arrowView, attribute: .height,         relatedBy: .equal,
                                                      toItem: nil,     attribute: .notAnAttribute, multiplier: 1, constant: target.heightArrow))
                constraints.append(NSLayoutConstraint(item: arrowView, attribute: .width,          relatedBy: .equal,
                                                      toItem: nil,     attribute: .notAnAttribute, multiplier: 1, constant: target.widthArrow))
                mask.addSubview(arrowView)
            }
            mask.addSubview(label)
            
            if let hole {
                addAbsConstraints(hole: hole)
            }
            
            removableConstraints.append(contentsOf: constraints)
            parent.addConstraints(constraints)
            // Advancing a tutorial after rotation does not cause another controller layout callback.
            refreshArrowConstraints()
            
            let handleNextTarget = {
                //If not persistent disappear before the next mask appear
                if target.persistant == false {
                    mask.removeHoles()
                    arrow?.isHidden = true
                    label.isHidden = true
                }
                self.targets.removeFirst()
                self.fireTargets()
            }
            
            if !target.breakPoint {
                if let duration = target.duration {
                    // Delay execution of my block for duration
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + duration) {
                        handleNextTarget()
                    }
                } else {
                    handleNextTarget()
                }
            }
        }
    }
    
    private func addAbsConstraints(hole: Hole) {
        // With the liquid glass UI its possible that some buttonss on button bars won't be
        // fully constrained, but their possition will be correct. So add some constraints to
        // tie the view to its current possition. The low priority ensures theres no conflicts.
        if let parent, let holeRect = hole.getRelRect(to: parent), let view = hole.view, view.isDescendant(of: parent) {
            let left      = NSLayoutConstraint(item:   view,   attribute: .left, relatedBy: .equal,
                                               toItem: parent, attribute: .left, multiplier: 1, constant: holeRect.minX)
            let top       = NSLayoutConstraint(item:   view,   attribute: .top,  relatedBy: .equal,
                                               toItem: parent, attribute: .top,  multiplier: 1, constant: holeRect.minY)
            // Lower the priority so we don't confilict with the main UI if it is already well
            // constrained
            left.priority = constraintPri
            top.priority  = constraintPri
            absConstraints.append(left)
            absConstraints.append(top)
            parent.addConstraint(left)
            parent.addConstraint(top)
        }
    }
    
    /**
     When a target's view is touched
     */
    private func tapped() {
        if let target = targets.first, target.isTappable || target.breakPoint {
            removeUiItems()
            targets.removeFirst()
            fireTargets()
        }
        if targets.isEmpty {
            removeUiItems()
            fireTargets()
        }
    }
}

