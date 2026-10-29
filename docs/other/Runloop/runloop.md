## 零：前言
声明：本文非原创，是我在整理自己iOS知识体系时，阅读到这篇文章，感觉作者整理的非常好，就转载到这里方便自己学习、备忘。

感谢作者崔江涛，如有侵权，请联系删除。

原文链接：https://www.cnblogs.com/kenshincui/p/6823841.html
原文作者：`崔江涛KenshinCui`

## 一：概述

`RunLoop`作为 iOS 中一个基础组件和线程有着千丝万缕的关系，同时也是很多常见技术的幕后功臣。尽管在平时多数开发者很少直接使用`RunLoop`，但是理解`RunLoop`可以帮助开发者更好的利用多线程编程模型，同时也可以帮助开发者解答日常开发中的一些疑惑。本文将从`RunLoop`源码着手，结合`RunLoop`的实际应用来逐步解开它的神秘面纱。

## 二: 开源的RunloopRef

通常所说的`RunLoop`指的是`NSRunloop`或者`CFRunloopRef`，`CFRunloopRef`是纯C的函数，而`NSRunloop`仅仅是`CFRunloopRef`的OC封装，并未提供额外的其他功能，因此下面主要分析`CFRunloopRef`，苹果已经开源了`CoreFoundation`源代码，因此很容易找到`CFRunloop`源代码👇。

> https://opensource.apple.com/source/CF

从代码可以看出`CFRunloopRef`其实就是`__CFRunloop`这个结构体指针（按照OC的思路我们可以将`RunLoop`看成一个对象），这个对象的运行才是我们通常意义上说的**运行循环**，核心方法是_`_CFRunloopRun()`，为了便于阅读就不再直接贴源代码，放一段伪代码方便大家阅读：

```c
int32_t __CFRunLoopRun( /** 5个参数 */ )
{
    // 通知即将进入runloop
    __CFRunLoopDoObservers(KCFRunLoopEntry);
    
    do
    {
        // 通知将要处理timer和source
        __CFRunLoopDoObservers(kCFRunLoopBeforeTimers);
        __CFRunLoopDoObservers(kCFRunLoopBeforeSources);
        
        // 处理非延迟的主线程调用
        __CFRunLoopDoBlocks();
        // 处理Source0事件
        __CFRunLoopDoSource0();
        
        if (sourceHandledThisLoop) {
            __CFRunLoopDoBlocks();
	     }
        // 如果有 Source1 (基于port) 处于 ready 状态，直接处理这个 Source1 然后跳转去处理消息。
        if (__Source0DidDispatchPortLastTime) {
            Boolean hasMsg = __CFRunLoopServiceMachPort();
            if (hasMsg) goto handle_msg;
        }
            
        // 通知 Observers: RunLoop 的线程即将进入休眠(sleep)。
        if (!sourceHandledThisLoop) {
            __CFRunLoopDoObservers(runloop, currentMode, kCFRunLoopBeforeWaiting);
        }
            
        // GCD dispatch main queue
        CheckIfExistMessagesInMainDispatchQueue();
        
        // 即将进入休眠
        __CFRunLoopDoObservers(kCFRunLoopBeforeWaiting);
        
        // 等待内核mach_msg事件
        mach_port_t wakeUpPort = SleepAndWaitForWakingUpPorts();
        
        // 等待。。。
        
        // 从等待中醒来
        __CFRunLoopDoObservers(kCFRunLoopAfterWaiting);
        
        // 处理因timer的唤醒
        if (wakeUpPort == timerPort)
            __CFRunLoopDoTimers();
        
        // 处理异步方法唤醒,如dispatch_async
        else if (wakeUpPort == mainDispatchQueuePort)
            __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__()
            
        // 处理Source1
        else
            __CFRunLoopDoSource1();
        
        // 再次确保是否有同步的方法需要调用
        __CFRunLoopDoBlocks();
        
    } while (!stop && !timeout);
    
    // 通知即将退出runloop
    __CFRunLoopDoObservers(CFRunLoopExit);
}
```

源代码尽管不算太长，但是如果不太熟悉的话面对这么一堆不知道做什么的函数调用还是会给人一种神秘感。但是现在可以不用逐行阅读，后面慢慢解开这层神秘面纱。现在只要了解上面的伪代码知道核心的方法`__CFRunLoopRun()`内部其实是一个`do-while`循环，这也正是`Runloop`运行的本质。执行了这个函数以后就一直处于“等待-处理”的循环之中，直到循环结束。只是不同于我们自己写的循环它在休眠时几乎不会占用系统资源，当然这是由于系统内核负责实现的，也是`Runloop`精华所在。

> 随着Swift的开源苹果也维护了一个Swift版本的跨平台`CoreFoundation`版本，除了mac平台它还是适配了 Linux 和 Windows 平台。但是鉴于目前很多关于 Runloop 的讨论都是以OC版展开的，所以这里也主要分析OC版本。
> `https://github.com/apple/swift-corelibs-foundation/`

下图描述了`Runloop`运行流程。基本描述了上面`Runloop`的核心流程，当然可以查看官方 [The RunLoop Sequence of Events描述](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)。


**我是图片001**
**我是图片001**

整个流程并不复杂（需要注意的就是_黄色_区域的消息处理中并不包含`source0`，因为它在循环开始之初就会处理），整个流程其实就是一种`Event Loop`的实现，其他平台均有类似的实现，只是这里叫做`Runloop`。但是既然`RunLoop`是一个消息循环，谁来管理和运行`Runloop`？那么它接收什么类型的消息？休眠过程是怎么样的？如何保证休眠时不占用系统资源？如何处理这些消息以及何时退出循环？还有一系列问题需要解开。

> 注意的是尽管`CFRunLoopPerformBlock`在上图中作为唤醒机制有所体现，但事实上执行`CFRunLoopPerformBlock`只是入队，下次`RunLoop`运行才会执行，而如果需要立即执行则必须调用`CFRunLoopWakeUp`。

## 三: Runloop Mode

从源码很容易看出，`Runloop`总是运行在某种特定的`CFRunLoopModeRef`下（每次运行`__CFRunLoopRun()`函数时必须指定`Mode`）。而通过`CFRunloopRef`对应结构体的定义可以很容易知道每种`Runloop`都可以包含若干个`Mode`，每个`Mode`又包含`Source/Timer/Observer`。每次调用`Runloop`的主函数`__CFRunLoopRun()`时必须指定一种`Mode`，这个Mode称为 **_currentMode** ，当切换`Mode`时必须退出当前`Mode`，然后重新进入`Runloop`以保证不同`Mode`的`Source/Timer/Observer`互不影响。

```c
struct __CFRunLoop {  // 部分
    CFRuntimeBase _base;
    pthread_mutex_t _lock; /* locked for accessing mode list */
    __CFPort _wakeUpPort; // used for CFRunLoopWakeUp 
    Boolean _unused;
    pthread_t _pthread;
    CFMutableSetRef _commonModes;
    CFMutableSetRef _commonModeItems;
    CFRunLoopModeRef _currentMode;
    CFMutableSetRef _modes;
    CFAbsoluteTime _runTime;
    CFAbsoluteTime _sleepTime;
    CFTypeRef _counterpart;
};

// ----------------------------------------

struct __CFRunLoopMode {  // 部分
    CFRuntimeBase _base;
    /* must have the run loop locked before locking this */
    pthread_mutex_t _lock;
    CFStringRef _name;
    Boolean _stopped;
    CFMutableSetRef _sources0;
    CFMutableSetRef _sources1;
    CFMutableArrayRef _observers;
    CFMutableArrayRef _timers;
    CFMutableDictionaryRef _portToV1SourceMap;
    __CFPortSet _portSet;
    CFIndex _observerMask;
};
```

系统默认提供的 Run Loop Modes 有`kCFRunLoopDefaultMode`(`NSDefaultRunLoopMode`)和`UITrackingRunLoopMode`，需要切换到对应的Mode 时只需要传入对应的名称即可。前者是系统默认的 Runloop Mode，例如进入iOS程序默认不做任何操作就处于这种 Mode 中，此时滑动`UIScrollView`，主线程就切换 Runloop 到`UITrackingRunLoopMode`，不再接受其他事件操作（除非你将其他 Source/Timer 设置到`UITrackingRunLoopMode`下）。

但是对于开发者而言经常用到的 Mode 还有一个`kCFRunLoopCommonModes`（`NSRunLoopCommonModes`）,其实这个并不是某种具体的 Mode，而是一种模式组合，在iOS系统中默认包含了 `NSDefaultRunLoopMode` 和`UITrackingRunLoopMode`；注意：并不是说 Runloop 会运行在`kCFRunLoopCommonModes`这种模式下，而是相当于分别注册了 `NSDefaultRunLoopMode` 和 `UITrackingRunLoopMode`。当然你也可以通过调用`CFRunLoopAddCommonMode()`方法将自定义 Mode 放到 `kCFRunLoopCommonModes`组合。

> 注意：我们常常还会碰到一些系统框架自定义 Mode，例如`Foundation`中`NSConnectionReplyMode`。还有一些系统私有 Mode，例如：`GSEventReceiveRunLoopMode`接受系统事件，`UIInitializationRunLoopMode`是App启动过程中初始化Mode。更多系统或框架Mode查看这里👇
> https://iphonedev.wiki/index.php/CFRunLoop

`CFRunLoopRef`和`CFRunloopMode`、`CFRunLoopSourceRef`/`CFRunloopTimerRef`/`CFRunLoopObserverRef`关系如下图：

**我是图片002**
**我是图片002**

一个RunLoop对象（`CFRunLoop`）中包含若干个运行模式（`CFRunLoopMode`）。而每一个运行模式下又包含若干个输入源（`CFRunLoopSource`）、定时源（`CFRunLoopTimer`）、观察者（`CFRunLoopObserver`）。

那么`CFRunLoopSourceRef`、`CFRunLoopTimerRef`和`CFRunLoopObserverRef`究竟是什么？它们在 Runloop 运行流程中起到什么作用呢？


## 四: Source

首先看一下官方 Runloop 结构图（注意下图的 Input Source Port 和前面流程图中的`Source0`并不对应，而是对应`Source1`。`Source1`和`Timer`都属于端口事件源，不同的是所有的`Timer`都共用一个端口“Mode Timer Port”，而每个`Source1`都有不同的对应端口）：

**我是图片003**
**我是图片003**

再结合前面 RunLoop 核心运行流程可以看出`Source0`(负责App内部事件，由App负责管理触发，例如`UITouch`事件)和`Timer`（又叫`Timer Source`，基于时间的触发器，上层对应`NSTimer`）是两个不同的 Runloop 事件源（当然`Source0`是`Input Source`中的一类，Input Source 还包括 Custom Input Source，由其他线程手动发出），RunLoop 被这些事件唤醒之后就会处理并调用事件处理方法（`CFRunLoopTimerRef`的回调指针和`CFRunLoopSourceRef`均包含对应的回调指针）。

但是对于`CFRunLoopSourceRef`除了`Source0`之外还有另一个版本就是`Source1`，`Source1`除了包含回调指针外包含一个`mach port`，和`Source0`需要手动触发不同，`Source1`可以监听系统端口和其他线程相互发送消息，它能够主动唤醒 RunLoop (由操作系统内核进行管理，例如`CFMessagePort`消息)。官方也指出可以自定义 Source，因此对于`CFRunLoopSourceRef`来说它更像一种协议，框架已经默认定义了两种实现，如果有必要开发人员也可以自定义，详细情况可以[查看官方文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)。

## 五: Observer

```c
struct __CFRunLoopObserver {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;
    CFRunLoopRef _runLoop;
    CFIndex _rlCount;
    CFOptionFlags _activities; /* immutable */
    CFIndex _order; /* immutable */
    CFRunLoopObserverCallBack _callout;	/* immutable */
};
```

相对来说`CFRunloopObserverRef`理解起来并不复杂，它相当于消息循环中的一个监听器，随时通知外部当前 RunLoop 的运行状态（它包含一个函数指针`_callout_`将当前状态及时告诉观察者）。具体的 Observer 状态如下：
```c
/* Run Loop Observer Activities */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0), // 进入RunLoop 
    kCFRunLoopBeforeTimers = (1UL << 1), // 即将开始Timer处理
    kCFRunLoopBeforeSources = (1UL << 2), // 即将开始Source处理
    kCFRunLoopBeforeWaiting = (1UL << 5), // 即将进入休眠
    kCFRunLoopAfterWaiting = (1UL << 6), // 从休眠状态唤醒
    kCFRunLoopExit = (1UL << 7), // 退出RunLoop
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

## 六: Call out

RunLoop 几乎所有的操作都是通过`Call out`进行回调的(无论是 Observer 的状态通知还是 Timer、Source 的处理)，而系统在回调时通常使用如下几个函数进行回调(换句话说你的代码其实最终都是通过下面几个函数来负责调用的，即使你自己监听Observer 也会先调用下面的函数然后间接通知你，所以在调用堆栈中经常看到这些函数)：

```c
static void __CFRUNLOOP_IS_CALLING_OUT_TO_AN_OBSERVER_CALLBACK_FUNCTION__();
static void __CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__();
static void __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__();
static void __CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__();
static void __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__();
static void __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE1_PERFORM_FUNCTION__();
```

例如在控制器的`touchBegin`中打入断点查看堆栈（由于`UIEvent`是`Source0`，所以可以看到一个`Source0`的`Call out`函数`CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION`调用）：

**我是图片004**
**我是图片004**

## 七: RunLoop休眠

其实对于 Event Loop 而言 RunLoop 最核心的事情就是保证线程在没有消息时休眠以避免占用系统资源，有消息时能够及时唤醒。RunLoop 的这个机制完全依靠系统内核来完成，具体来说是苹果操作系统核心组件`Darwin`中的`Mach`来完成的（[Darwin是开源的](https://opensource.apple.com/)）。可以从下图最底层`Kernel`中找到`Mach`：

**我是图片005**
**我是图片005**

`Mach`是`Darwin`的核心，可以说是内核的核心，提供了进程间通信（IPC）、处理器调度等基础服务。在`Mach`中，进程、线程间的通信是以消息的方式来完成的，消息在两个`Port`之间进行传递（这也正是`Source1`之所以称之为 Port-based Source 的原因，因为它就是依靠系统发送消息到指定的Port来触发的）。消息的发送和接收使用`<mach/message.h>`中的`mach_msg()`函数（事实上苹果提供的 Mach API 很少，并不鼓励我们直接调用这些API）：

**我是图片006**
**我是图片006**

而`mach_msg()`的本质是一个调用`mach_msg_trap()`,这相当于一个系统调用，会触发内核状态切换。当程序静止时，RunLoop 停留在
```c
__CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy)
```
而这个函数内部就是调用了`mach_msg`让程序处于休眠状态。

RunLoop 这种有事做事，没事休息的机制其实就是`用户态`和`内核态`的互相转化。`用户态`和`内核态`在 Linux 和 Unix 系统中，是基本概念，是操作系统的两种运行级别，他们的权限不一样，由于系统的资源是有限的，比如网络、内存等，所以为了优化性能，降低电量消耗，提高资源利用率，所以内核底层就这么设计了。

## 八: Runloop和线程的关系

Runloop 是基于`pthread`进行管理的，`pthread`是基于 C 的跨平台多线程操作底层API。它是 mach thread 的上层封装（可以参见[Kernel Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/KernelProgramming/Mach/Mach.html)），和`NSThread`一一对应（而`NSThread`是一套面向对象的API，所以在iOS开发中我们也几乎不用直接使用`pthread`）。

**我是图片007**
**我是图片007**

苹果开发的接口中并没有直接创建 Runloop 的接口，如果需要使用 Runloop 通常`CFRunLoopGetMain()`和`CFRunLoopGetCurrent()`两个方法来获取（通过上面的源代码也可以看到，核心逻辑在`_CFRunLoopGet_`当中）,通过代码并不难发现其实只有当我们使用线程的方法主动 get Runloop 时才会在第一次创建该线程的Runloop，同时将它保存在全局的`Dictionary`中（**线程和Runloop是一一对应**），默认情况下线程并不会创建 Runloop（主线程的Runloop比较特殊，任何线程创建之前都会保证主线程已经存在 Runloop），同时在线程结束的时候也会销毁对应的Runloop。

iOS开发过程中对于开发者而言更多的使用的是`NSRunloop`,它默认提供了三个常用的run方法：
```objc
- (void)run; 
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (void)runUntilDate:(NSDate *)limitDate;
```

- `run:`方法对应上面`CFRunloopRef`中的`CFRunLoopRun`并不会退出，除非调用`CFRunLoopStop()`;通常如果想要永远不会退出 RunLoop 才会使用此方法，否则可以使用`runUntilDate:`。
- `runMode:beforeDate:`则对应`CFRunLoopRunInMode(mode,limiteDate,true)`方法,只执行一次，执行完就退出；通常用于手动控制 RunLoop（例如在while循环中）。
- `runUntilDate:`方法其实是`CFRunLoopRunInMode(kCFRunLoopDefaultMode,limiteDate,false)`，执行完并不会退出，继续下一次RunLoop直到timeout。

## 九: RunLoop应用

### 9.1 NSTimer

前面一直提到 Timer Source 作为事件源，事实上它的上层对应就是`NSTimer`（其实就是`CFRunloopTimerRef`）这个开发者经常用到的定时器（底层基于使用`mk_timer`实现），甚至很多开发者接触 RunLoop 还是从`NSTimer`开始的。其实`NSTimer`定时器的触发正是基于 RunLoop 运行的，所以使用`NSTimer`之前必须注册到 RunLoop，但是 RunLoop 为了节省资源并不会在非常准确的时间点调用定时器，如果一个任务执行时间较长，那么当错过一个时间点后只能等到下一个时间点执行，并不会延后执行（`NSTimer`提供了一个`tolerance`属性用于设置宽容度，如果确实想要使用`NSTimer`并且希望尽可能的准确，则可以设置此属性）。

`NSTimer`的创建通常有两种方式，尽管都是类方法，一种是`timerWithXXX`，另一种`scheduedTimerWithXXX`。

```objc
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti invocation:(NSInvocation *)invocation repeats:(BOOL)yesOrNo;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget selector:(SEL)aSelector userInfo:(nullable id)userInfo repeats:(BOOL)yesOrNo;
```

二者最大的区别就是后者除了创建一个定时器外会自动以`NSDefaultRunLoopModeMode`添加到当前线程 RunLoop 中，不添加到 RunLoop中的`NSTimer`是无法正常工作的。例如下面的代码中如果`timer2`不加入到RunLoop 中是无法正常工作的。同时注意如果滚动`UIScrollView`（UITableView、UICollectionview是类似的）二者是无法正常工作的，但是如果将`NSDefaultRunLoopMode`改为`NSRunLoopCommonModes`则可以正常工作，这也解释了前面介绍的 Mode 内容。

```objc
@interface BViewController ()
@property (nonatomic, weak) NSTimer *timer1;
@property (nonatomic, weak) NSTimer *timer2;
@end

@implementation BViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blueColor];

    // timer1创建后会自动以NSDefaultRunLoopMode默认模式添加到当前RunLoop中，所以可以正常工作
    self.timer1 = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timeInterval:) userInfo:nil repeats:YES];
    NSTimer *tempTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(timeInterval:) userInfo:nil repeats:YES];
    
    // 如果不把timer2添加到RunLoop中是无法正常工作的(注意如果想要在滚动UIScrollView时timer2可以正常工作可以将NSDefaultRunLoopMode改为NSRunLoopCommonModes)
    [[NSRunLoop currentRunLoop] addTimer:tempTimer forMode:NSDefaultRunLoopMode];
    self.timer2 = tempTimer;
    
    CGRect rect = [UIScreen mainScreen].bounds;
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectInset(rect, 0, 200)];
    [self.view addSubview:scrollView];
    
    UIView *contentView = [[UIView alloc] initWithFrame:CGRectInset(scrollView.bounds, -100, -100)];
    contentView.backgroundColor = [UIColor redColor];
    [scrollView addSubview:contentView];
    scrollView.contentSize = contentView.frame.size;
}

- (void)timeInterval:(NSTimer *)timer {
    if (self.timer1 == timer) {
        NSLog(@"timer1...");
    } else {
        NSLog(@"timer2...");
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)dealloc {
    NSLog(@"BViewController dealloc...");
}
@end
```

注意上面代码中`UIViewController`对`timer1`和`timer2`并没有强引用，对于普通的对象而言，执行完`viewDidLoad`方法之后（准确的说应该是执行完`viewDidLoad`方法后的的一个 RunLoop 运行结束）二者应该会被释放，但事实上二者并没有被释放。原因是：为了确保定时器正常运转，当加入到 RunLoop 以后系统会对`NSTimer`执行一次`retain`操作（特别注意⚠️：`timer2`创建时并没直接赋值给`timer2`，原因是`timer2`是`weak`属性，如果直接赋值给`timer2`会被立即释放，因为`timerWithXXX`方法创建的`NSTimer`默认并没有加入 RunLoop，只有后面加入 RunLoop 以后才可以将引用指向`timer2`）。

但是即使使用了弱引用，上面的代码中`BViewController`也无法正常释放，原因是在创建`NSTimer2`时指定了`target`为`self`，这样一来造成了`timer1`和`timer2`对`BViewController`有一个强引用。

解决这个问题的方法通常有两种：一种是将`target`分离出来独立成一个对象（在这个对象中创建`NSTimer`并将对象本身作为`NSTimer`的`target`），控制器通过这个对象间接使用`NSTimer`；另一种方式的思路仍然是转移`target`，只是可以直接增加`NSTimer`扩展（分类），让`NSTimer`自身做为`target`，同时可以将操作`selector`封装到`block`中。后者相对优雅，也是目前使用较多的方案，如果你可以确保代码只在 iOS 10 后运行就可以使用 iOS 10 新增的系统级block方案（下面的代码中已经贴出这种方法）。

当然使用上面第二种方法可以解决控制器无法释放的问题，但是会发现即使控制器被释放了两个定时器仍然正常运行，要解决这个问题就需要调用`NSTimer`的`invalidate`方法（注意：无论是重复执行的定时器还是一次性的定时器只要调用`invalidate`方法则会变得无效，只是一次性的定时器执行完操作后会自动调用`invalidate`方法）。修改后的代码如下：

```objc
@implementation BViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blueColor];

    self.timer1 = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        NSLog(@"timer1...");
    }];
    NSTimer *tempTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        NSLog(@"timer2...");
    }];
    [[NSRunLoop currentRunLoop] addTimer:tempTimer forMode:NSDefaultRunLoopMode];
    self.timer2 = tempTimer;
    
    CGRect rect = [UIScreen mainScreen].bounds;
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectInset(rect, 0, 200)];
    [self.view addSubview:scrollView];
    
    UIView *contentView = [[UIView alloc] initWithFrame:CGRectInset(scrollView.bounds, -100, -100)];
    contentView.backgroundColor = [UIColor redColor];
    [scrollView addSubview:contentView];
    scrollView.contentSize = contentView.frame.size;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self dismissViewControllerAnimated:true completion:nil];
}

- (void)dealloc {
    [self.timer1 invalidate];
    [self.timer2 invalidate];
    NSLog(@"BViewController dealloc...");
}
@end
```

其实和定时器相关的另一个问题大家也经常碰到，那就是`NSTimer`不是一种实时机制，[官方文档](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Timers/Articles/timerConcepts.html)明确说明在一个循环中如果 RunLoop 没有被识别（这个时间大概在50-100ms）或者说当前 RunLoop 在执行一个长的`call out`（例如执行某个循环操作）则`NSTimer`可能就会存在误差，RunLoop 在下一次循环中继续检查并根据情况确定是否执行（`NSTimer`的执行时间总是固定在一定的时间间隔，例如1:00:00、1:00:01、1:00:02、1:00:05则跳过了第4、5次运行循环）。

要演示这个问题请看下面的例子（注意：有些示例中可能会让一个线程中启动一个定时器，再在主线程启动一个耗时任务来演示这个问，如果实际测试可能效果不会太明显，因为现在的iPhone都是多核运算的，这样一来这个问题会变得相对复杂，因此下面的例子选择在同一个 RunLoop 中即加入定时器和执行耗时任务）

```objc
@interface ViewController ()
@property (nonatomic, weak) NSTimer *timer1;
@property (nonatomic, strong) NSThread *thread1;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor redColor];
    
    // 由于下面的方法无法拿到NSThread的引用，也就无法控制线程的状态
    // [NSThread detachNewThreadSelector:@selector(performTask) toTarget:self withObject:nil];
    self.thread1 = [[NSThread alloc] initWithTarget:self selector:@selector(performTask) object:nil];
    [self.thread1 start];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.thread1 cancel];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc {
    [self.timer1 invalidate];
    NSLog(@"ViewController dealloc.");
}

- (void)performTask {
    // 使用下面的方式创建定时器虽然会自动加入到当前线程的RunLoop中，但是除了主线程外其他线程的RunLoop默认是不会运行的，必须手动调用
    __weak typeof(self) weakSelf = self;
    self.timer1 = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if ([NSThread currentThread].isCancelled) {
            //[NSObject cancelPreviousPerformRequestsWithTarget:weakSelf selector:@selector(caculate) object:nil];
            //[NSThread exit];
            [weakSelf.timer1 invalidate];
        }
        NSLog(@"timer1...");
    }];
    
    NSLog(@"runloop before performSelector: %@", [NSRunLoop currentRunLoop]);
    
    // 区分直接调用和「performSelector:withObject:afterDelay:」区别,下面的直接调用无论是否运行RunLoop一样可以执行，但是后者则不行。
    // [self caculate];
    [self performSelector:@selector(caculate) withObject:nil afterDelay:2.0];

    // 取消当前RunLoop中注册selector（注意：只是当前RunLoop，所以也只能在当前RunLoop中取消）
    // [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(caculate) object:nil];
    NSLog(@"runloop after performSelector:%@", [NSRunLoop currentRunLoop]);
    
    // 非主线程RunLoop必须手动调用
    [[NSRunLoop currentRunLoop] run];
    
    NSLog(@"注意：如果RunLoop不退出（运行中），这里的代码并不会执行，RunLoop本身就是一个循环.");
}

- (void)caculate {
    for (int i = 0;i < 9999;++i) {
        NSLog(@"%i, %@",i, [NSThread currentThread]);
        if ([NSThread currentThread].isCancelled) {
            return;
        }
    }
}
@end
```

如果运行并且不退出上面的程序会发现，前两秒`NSTimer`可以正常执行，但是两秒后由于同一个RunLoop中循环操作的执行造成定时器跳过了中间执行的机会一直到`caculator`循环完毕，这也正说明了`NSTimer`不是实时系统机制的原因。

但是以上程序还有几点需要说明一下：

- 1.`NSTimer`会对`Target`进行强引用直到任务结束或`exit`之后才会释放。如果上面的程序没有进行线程`cancel`而终止任务则及时关闭控制器也无法正确释放。
- 2.非主线程的 RunLoop 并不会自动运行（同时注意默认情况下非主线程的RunLoop并不会自动创建，直到第一次使用），RunLoop 运行必须要在加入`NSTimer`或`Source0`、`Sourc1`、`Observer`输入后运行否则会直接退出。例如上面代码如果`run`放到`NSTimer`创建之前则既不会执行定时任务也不会执行循环运算。
- 3.`performSelector:withObject:afterDelay:`执行的本质还是通过创建一个`NSTimer`然后加入到当前线程RunLoop（通而过前后两次打印 RunLoop 信息可以看到此方法执行之后RunLoop的 timer 会增加1个。类似的还有`performSelector:onThread:withObject:afterDelay:`，只是它会在另一个线程的RunLoop中创建一个Timer），所以此方法事实上在任务执行完之前会对触发对象形成引用，任务执行完进行释放（例如上面会对`ViewController`形成引用，注意：`performSelector:withObject:`等方法则等同于直接调用，原理与此不同）。
- 4.同时上面的代码也充分说明了RunLoop是一个循环事实，run方法之后的代码不会立即执行，直到RunLoop退出。
- 5.上面程序的运行过程中如果突然`dismiss`，则程序的实际执行过程要分为两种情况考虑：如果循环任务`caculate`还没有开始则会在`timer1`中停止`timer1`运行（停止了线程中第一个任务），然后等待`caculate`执行并`break`（停止线程中第二个任务）后线程任务执行结束释放对控制器的引用；如果循环任务`caculate`执行过程中`dismiss`则`caculate`任务执行结束，等待`timer1`下个周期运行（因为当前线程的RunLoop并没有退出，`timer1`引用计数器并不为0）时检测到线程取消状态则执行`invalidate`方法（第二个任务也结束了），此时线程释放对于控制器的引用。

> `CADisplayLink`是一个执行频率（FPS）和屏幕刷新相同（可以修改`preferredFramesPerSecond`改变刷新频率）的定时器，它也需要加入到RunLoop才能执行。与`NSTimer`类似，`CADisplayLink`同样是基于`CFRunloopTimerRef`实现，底层使用`mk_timer`（可以比较加入到 RunLoop 前后 RunLoop 中 timer 的变化）。和`NSTimer`相比它精度更高（尽管`NSTimer`也可以修改精度），不过和`NStimer`类似的是如果遇到大任务它仍然存在丢帧现象。通常情况下`CADisaplayLink`用于构建帧动画，看起来相对更加流畅，而`NSTimer`则有更广泛的用处。

### 9.2 AutoreleasePool

`AutoreleasePool`是另一个与 RunLoop 相关讨论较多的话题。其实从 RunLoop 源代码分析，`AutoreleasePool`与 RunLoop 并没有直接的关系，之所以将两个话题放到一起讨论最主要的原因是因为在iOS应用启动后会注册两个 Observer 管理和维护`AutoreleasePool`。不妨在应用程序刚刚启动时打印`currentRunLoop`可以看到系统默认注册了很多个 Observer，其中有两个 Observer 的`callout`都是`_ wrapRunLoopWithAutoreleasePoolHandler`，这两个是和自动释放池相关的两个监听。

```objc
<CFRunLoopObserver 0x6080001246a0 [0x101f81df0]>{valid = Yes, activities = 0x1, repeats = Yes, order = -2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x1020e07ce), context = <CFArray 0x60800004cae0 [0x101f81df0]>{type = mutable-small, count = 0, values = ()}}
<CFRunLoopObserver 0x608000124420 [0x101f81df0]>{valid = Yes, activities = 0xa0, repeats = Yes, order = 2147483647, callout = _wrapRunLoopWithAutoreleasePoolHandler (0x1020e07ce), context = <CFArray 0x60800004cae0 [0x101f81df0]>{type = mutable-small, count = 0, values = ()}}
```

第一个 Observer 会监听 RunLoop 的进入，它会回调`objc_autoreleasePoolPush()`向当前的`AutoreleasePoolPage`增加一个哨兵对象标志创建自动释放池。这个 Observer 的order是-2147483647优先级最高，确保发生在所有回调操作之前。

第二个 Observer 会监听 RunLoop 的进入休眠和即将退出 RunLoop 两种状态，在即将进入休眠时会调用`objc_autoreleasePoolPop()`和 `objc_autoreleasePoolPush()`根据情况从最新加入的对象一直往前清理直到遇到哨兵对象。而在即将退出 RunLoop 时会调用`objc_autoreleasePoolPop()`释放自动自动释放池内对象。这个 Observer 的order是2147483647，优先级最低，确保发生在所有回调操作之后。

主线程的其他操作通常均在这个`AutoreleasePool`之内（main函数中），以尽可能减少内存维护操作(当然你如果需要显式释放【例如循环】时可以自己创建`AutoreleasePool`否则一般不需要自己创建)。

其实在应用程序启动后系统还注册了其他 Observer（例如即将进入休眠时执行注册回调`_UIGestureRecognizerUpdateObserver`用于手势处理、回调为_ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv的Observer用于界面实时绘制更新）和多个`Source1`（例如context为`CFMachPort`的`Source1`用于接收硬件事件响应进而分发到应用程序一直到`UIEvent`），这里不再一一详述。

### 9.3 UI更新

如果打印App启动之后的主线程 RunLoop 可以发现另外一个 callout 为`_ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv`的 Observer，这个监听专门负责UI变化后的更新，比如修改了frame、调整了UI层级（`UIView`/`CALayer`）或者手动设置了`setNeedsDisplay:`/`setNeedsLayout:`之后就会将这些操作提交到全局容器。而这个 Observer 监听了主线程 RunLoop 的即将进入休眠和退出状态，一旦进入这两种状态则会遍历所有的UI更新并提交进行实际绘制更新。

通常情况下这种方式是完美的，因为除了系统的更新，还可以利用`setNeedsDisplay`等方法手动触发下一次 RunLoop 运行的更新。但是如果当前正在执行大量的逻辑运算可能UI的更新就会比较卡，因此facebook推出了[Texture](https://github.com/texturegroup/texture/)来解决这个问题。

`Texture`其实是将UI排版和绘制运算尽可能放到后台，将UI的最终更新操作放到主线程（这一步也必须在主线程完成），同时提供一套类`UIView`或`CALayer`的相关属性，尽可能保证开发者的开发习惯。这个过程中`Texture`在主线程 RunLoop 中增加了一个Observer 监听即将进入休眠和退出 RunLoop 两种状态,收到回调时遍历队列中的待处理任务一一执行。

### 9.4 NSURLConnection

一旦启动`NSURLConnection`以后就会不断调用`delegate`方法接收数据，这样一个连续的的动作正是基于 RunLoop 来运行。

一旦`NSURLConnection`设置了`delegate`会立即创建一个线程`com.apple.NSURLConnectionLoader`，同时内部启动 RunLoop 并在`NSDefaultMode`模式下添加4个`Source0`。其中`CFHTTPCookieStorage`用于处理cookie;`CFMultiplexerSource`负责各种`delegate`回调并在回调中唤醒`delegate`内部的RunLoop（通常是主线程）来执行实际操作。

早期版本的`AFNetworking`库也是基于`NSURLConnection`实现，为了能够在后台接收delegate回调`AFNetworking`内部创建了一个空的线程并启动了RunLoop，当需要使用这个后台线程执行任务时`AFNetworking`通过`performSelector:onThread:`将这个任务放到后台线程的 RunLoop 中。

## 十: GCD和RunLoop的关系

在 RunLoop 的源代码中可以看到用到了GCD的相关内容，但是 RunLoop 本身和GCD并没有直接的关系。当调用了`dispatch_async(dispatch_get_main_queue(), ^(void)block)`时`libDispatch`会向主线程 RunLoop 发送消息唤醒 RunLoop，RunLoop 从消息中获取block，并且在`__CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__`回调里执行这个block。不过这个操作仅限于主线程，其他线程`dispatch`操作是全部由`libDispatch`驱动的。

## 十一: 更多RunLoop使用

写到了这里，那么除了这些究竟在实际开发过程中我们自己能不能适当的使用 RunLoop 帮我们做一些事情呢？

思考这个问题其实只要看`RunLoopRef`的包含关系就知道了，RunLoop包含多个Mode，而它的Mode又是可以自定义的，这么推断下来其实无论是`Source1`、`Timer`还是`Observer`开发者都可以利用，但是通常情况下不会自定义Timer，更不会自定义一个完整的Mode，利用更多的其实是Observer和Mode的切换。

例如很多人都熟悉的使用`perfromSelector`在默认模式下设置图片，防止`UITableView`滚动卡顿:
```objc
[imgView performSelector:@selector(setImage:) withObject:myImage afterDelay:0.0 inModes:@NSDefaultRunLoopMode]
```

还有sunnyxx的[UITableView+FDTemplateLayoutCell](https://github.com/forkingdog/UITableView-FDTemplateLayoutCell)利用 Observer 在界面空闲状态下计算出`UITableViewCell`的高度并进行缓存。

> 关于如何自定义一个[Custom Input Source](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)官网给出了详细的流程。

### 11.1: 自定义常驻线程

```objc
// 1.全局的，或者static的，目的是保持`NSThread`
@property (nonatomic, strong) NSThread *myThread;

// 2.初始化线程并启动
self.myThread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
self.myThread.name = @"myThread";
[self.myThread start];

// 3.启动RunLoop，子线程的RunLoop默认是停止的
- (void)run {
    // 只要往RunLoop中添加了 timer、source或者observer就会继续执行
    // 一个RunLoop通常必须包含一个输入源或者定时器来监听事件
    // 如果一个都没有，RunLoop启动后立即退出。
    @autoreleasepool {
        // 添加一个input source
        NSRunLoop *rl = [NSRunLoop currentRunLoop];
        [rl addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [rl run];
// 2、添加一个定时器
// NSTimer *timer = [NSTimer timerWithTimeInterval:2.0 target:self selector:@selector(test) userInfo:nil repeats:YES];
// [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
// [[NSRunLoop currentRunLoop] run];
    }
}
```

这样`myThread`这个线程就会一直存在，当需要使用此线程在处理一些事情的时候就这么调用:
```objc
[self performSelector:@selector(act) onThread:self.thread withObject:nil waitUntilDone:NO];

- (void)act {
    NSLog(@"111");
    NSLog(@"%@", [NSThread currentThread]);
}
```






















