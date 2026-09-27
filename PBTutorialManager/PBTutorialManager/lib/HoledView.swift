//
//  HoledView.swift
//  PBTutorialManager
//
//  Created by Thomas Grocutt on 02/03/2019.
//  Copyright © 2019 Thomas Grocutt. All rights reserved.
//
//  Heavily based on JMHoledView by Jerome Morissard
//  Copyright © 2015 Jerome Morissard. All rights reserved.

import Foundation
import UIKit


class HoledView: UIView {
    private weak var tapGesture:             UITapGestureRecognizer?
    private weak var manager:                TutorialManager? = nil
                 var dimingColor             = UIColor.black.withAlphaComponent(0.7)
                 var holeColor               = UIColor.clear
    
    init(frame: CGRect, manager: TutorialManager) {
        super.init(frame: frame)
        self.manager = manager
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor      = UIColor.clear
        let tapGesture       = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
        tapGesture.isEnabled = false
        addGestureRecognizer(tapGesture)
        self.tapGesture      = tapGesture
        // The content needs to be redrawn when the size / layout of the view changes
        contentMode          = .redraw
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override var frame: CGRect {
        didSet {
            if frame.size != oldValue.size {
                setNeedsUpdateConstraints()
            }
        }
    }
    
    override var bounds: CGRect {
        didSet {
            if bounds.size != oldValue.size {
                setNeedsUpdateConstraints()
            }
        }
    }
    
    override func updateConstraints() {
        manager?.updateConstraints(holes: holes)
        super.updateConstraints()
    }
    
    @objc func viewTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.view != nil else {
            return
        }
        tapListener?()
    }
    
    var tapListener: (() -> Void)? = nil {
        didSet {
            tapGesture?.isEnabled = tapListener != nil
        }
    }
    
    private var holes = [Hole]() {
        didSet {
            setNeedsDisplay()
        }
    }
    
    func removeHoles() {
        holes.removeAll()
    }
    
    func addRectHole(view: UIView, cornerRadius: CGFloat? = nil) -> Hole {
        let hole = Hole(rectFor: view, cornerRadius: cornerRadius)
        holes.append(hole)
        return hole
    }
    
    func addElipse(view: UIView) -> Hole {
        let hole = Hole(circleFor: view)
        holes.append(hole)
        return hole
    }

    override func draw(_ bgRect: CGRect) {
        super.draw(bgRect)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        // Set the current color to the diming color and fill the whole rect
        context.setFillColor(dimingColor.cgColor)
        context.fill(bgRect)
        
        // Set the current color back to transparent, and process each hole in turn
        context.setFillColor(holeColor.cgColor)
        context.setBlendMode(.clear)
        holes.forEach() { hole in
            if let absRect = hole.getRelRect(to: self) {
                switch hole.shape {
                case .rect:
                    context.fill(absRect)
                case .roundedRect:
                    let path = UIBezierPath(roundedRect: absRect, cornerRadius: hole.cornerRadius!)
                    context.addPath(path.cgPath)
                    context.fillPath()
                case .elipse:
                    context.fillEllipse(in: absRect)
                }
            }
        }
    }
}


struct Hole {
         let shape:        HoleShape
         let cornerRadius: CGFloat?
    weak var view:         UIView?
   
    
    init(rectFor view: UIView, cornerRadius: CGFloat? = nil) {
        self.view         = view
        self.cornerRadius = cornerRadius
        shape             = cornerRadius == nil ? .rect : .roundedRect
    }
    
    init(circleFor view: UIView) {
        self.view    = view
        shape        = .elipse
        cornerRadius = nil
    }
    
    func getRelRect(to relativeView: UIView) -> CGRect? {
        var curView = view
        var rect    = curView?.frame
        while let curSuperView = curView?.superview, curSuperView != relativeView.superview {
            let origin = curSuperView.frame.origin
            rect       = rect?.offsetBy(dx: origin.x, dy: origin.y)
            if let scrollView = curSuperView as? UIScrollView {
                let offset = scrollView.contentOffset
                rect       = rect?.offsetBy(dx: -offset.x, dy: -offset.y)
            }
            curView = curSuperView
        }
        rect = rect?.intersection(relativeView.frame)
        if let unwrappedRect = rect, !unwrappedRect.origin.x.isFinite || !unwrappedRect.size.width.isFinite ||
                                     !unwrappedRect.origin.y.isFinite || !unwrappedRect.size.height.isFinite {
            rect = nil
        }
        return rect
    }
}


public enum HoleShape {
    case rect
    case roundedRect
    case elipse
}
