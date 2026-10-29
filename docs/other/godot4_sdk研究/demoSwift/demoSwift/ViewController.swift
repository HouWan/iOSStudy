//
//  ViewController.swift
//  Created by hou.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        GodotIOSSkyBridge.shared().listener = self
    }

    /// 点击 初始化引擎 按钮
    @IBAction func clickInitEngineBtn(_ sender: UIButton) {
        print("点击 初始化引擎 按钮")
        
//        guard let pckPath = Bundle.main.path(forResource: "room", ofType: "pck", inDirectory: "scene") else {
//            print("Error: not found scene file")
//            return
//        }
//        
//        let engine = GodotEngineManager.shared()
//        let res = engine.startEngineRuntime(pckPath)
//        print("Start Engine Result: ", res)
        
        let kbv = SceneKeyBoardView(frame: .zero)
        kbv.frame = self.view.bounds
        kbv.show()
    }
    
    /// 点击 进入场景 按钮
    @IBAction func clickEnterSceneBtn(_ sender: UIButton) {
        print("点击 进入场景 按钮")

        if let gameController = GodotEngineManager.shared().gameControlller() {
            navigationController?.pushViewController(gameController, animated: true)
        }
    }

}


// =============================================================================
// MARK: - GodotBridgeProtocol
// =============================================================================

extension ViewController: GodotBridgeProtocol {
    
    /// Godot --> iOS原生   不需要应答 或者 需要异步应答 消息体里面做出区分
    /// 参数`message`是一个JSON字符串
    func get_godot_message(_ message: String?) {
        guard let msgJson = message else { return }
        
        let jsonData = Data(msgJson.utf8)
        let json = (try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]) ?? [:]
        
        print("----> ", json)
        
        if msgJson.contains("HelloGodot") {
            let plazaPage = "{\"type\":\"open\",\"path\": \"Plaza\"}"
            GodotIOSSkyBridge.shared().sendToGodot(plazaPage)
        }
        
    }
    
    /// Godot --> iOS原生   需要应答  同步应答
    /// 参数`message`是一个JSON字符串
    func get_godot_sync_message(_ message: String?) -> String {
        return ""
    }
}



