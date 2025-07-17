//
//  GodotIOSSkyBridge.h
//  Created by HouWan
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GodotBridgeProtocol <NSObject>
@required
/// Godot --> iOS原生   不需要应答 或者 需要异步应答 消息体里面做出区分
- (void)get_godot_message:(nullable NSString *)message;
/// Godot --> iOS原生   需要应答  同步应答
- (nonnull NSString *)get_godot_sync_message:(nullable NSString *)message;


@end



@interface GodotIOSSkyBridge : NSObject

@property (nonatomic, weak) id<GodotBridgeProtocol> listener;

+ (instancetype)shared;

/// iOS --> Godot 正常的 App --> godot 发送
- (void)sendToGodot:(nonnull NSString *)message NS_SWIFT_NAME(sendToGodot(_:));

@end

NS_ASSUME_NONNULL_END
