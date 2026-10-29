//
//  SceneKeyBoardView.swift
//  Created by hou
//

import UIKit


fileprivate let maxHeight = 100.0
fileprivate let minHeight = 35.0


class SceneKeyBoardView: UIView {
    
    private let containerView: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.85)
        return view
    }()
    
    private let textView: UITextView = {
        let view = UITextView(frame: .zero)
        view.text = ""
        view.backgroundColor = .clear
        view.textColor = .white
        view.font = UIFont.systemFont(ofSize: 15)
        view.keyboardAppearance = .dark
        view.inputAccessoryView = UIView(frame: .zero)
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor(red: 0, green: 0.94, blue: 1, alpha: 1).cgColor
        view.layer.cornerRadius = 16
        return view
    }()
    
    private let okButton: UIButton = {
        let view = UIButton(type: .custom)
        view.setTitle("Send", for: .normal)
        view.setTitleColor(.white, for: .normal)
        view.backgroundColor = UIColor(red: 0, green: 0.94, blue: 1, alpha: 1)
        view.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        view.layer.cornerRadius = 16
        return view
    }()
    
    private var textSizeObserver: NSKeyValueObservation?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.textSizeObserver = nil
    }
    
    private func configUI() {
        addSubview(containerView)
        containerView.addSubview(textView)
        containerView.addSubview(okButton)
        
        textView.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
    }
    
    // KVO 4 textContentSize
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let kp = keyPath, kp == "contentSize" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateUIFrame()
    }
    
    private func updateUIFrame() {
        var tx: CGFloat = 0, ty : CGFloat = 0, tw: CGFloat = 0, th: CGFloat = 0
        
        ty = 100
        tw = self.frame.width
        th = 70
        containerView.frame = CGRect(x: tx, y: ty, width: tw, height: th)
        
        tw = 70
        ty = 20
        th = 40
        tx = self.frame.width - tw - 20
        okButton.frame = CGRect(x: tx, y: ty, width: tw, height: th)
        
        tx = 20
        tw = okButton.frame.minX - tx - 20
        textView.frame = CGRect(x: tx, y: ty, width: tw, height: th)
    }
    
    func show() {
        guard let apd = UIApplication.shared.delegate as? AppDelegate, 
              let appWindow = apd.window else { return }
        appWindow.addSubview(self)
//        textView.becomeFirstResponder()
    }
    
}
