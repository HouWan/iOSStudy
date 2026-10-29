//
//  GodotEngineManager.h
//  Created by hou
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 控制器的生命周期枚举
typedef NS_ENUM (NSInteger, GEControllerLifecycle) {
    unknown,
    didLoad,
    willAppear,
    didAppear,
    willDisappear,
    didDisappear
};


@protocol GodotEngineProtocol <NSObject>

// 游戏控制器生命周期的改变的代理回调
- (void)gameControlllerTo:(GEControllerLifecycle)lifecycle;

@end


/// 引擎管理
@interface GodotEngineManager : NSObject

/// 单例
+ (nonnull GodotEngineManager *)shared;

/// 代理
@property (nonatomic, weak, nullable) id<GodotEngineProtocol> engineDelegate;

/// 游戏控制器当前的生命周期
@property (nonatomic, assign) GEControllerLifecycle lifecycle;

/// PCK路径
@property (nonatomic, copy, nullable) NSString *pckPath;

/// 初始化
- (int)startEngineRuntime:(nullable NSString *)pckPath;

/// 是否暂停游戏引擎 YES暂停 NO不暂停
- (void)pause:(BOOL)pause;

/// 游戏引擎的Controlller
- (nullable UIViewController *)gameControlller;

@end

NS_ASSUME_NONNULL_END
