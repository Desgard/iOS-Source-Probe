> 作者：李孛

> 原文地址：[Route 1](http://kylinroc.github.io/foundation-run-loop.html)

# Run Loop 记录与源码注释

## Run Loop 是什么

广义上的来说，run loop 就是所谓的 [event loop](https://en.wikipedia.org/wiki/Event_loop)，或者称之为「事件循环」或者「事件分发器」。Event loop 是 [event-driven programming](https://en.wikipedia.org/wiki/Event-driven_programming)（事件驱动编程）非常重要的组成部分，而事件驱动编程则是 GUI 程序的最常见编程方式（现在似乎在服务器端也有很多应用，但在 GUI 编程方面肯定是绕不过去）。

Event loop 的思想非常简单，用下面的伪代码来表示：

```c
int main(void) {
    初始化();
    while (message != 退出) {
        处理事件(message);
        message = 获取下一个事件();
    }
    return 0;
}
```

回到 macOS/iOS 平台上，对于 event loop 的具体实现有两个：

1. Foundation 框架中的 `NSRunLoop`
2. Core Foundation 框架中的 `CFRunLoop`

其中 `NSRunLoop` 是对 `CFRunLoop` 的简单封装，需要着重研究的只有 `CFRunLoop`。

## CFRunLoop

`CFRunLoop` 的实际实现与 event loop 的思想还是有很大区别的。首先，使用 `CFRunLoop` 的主体是使用 `CFRunLoop` 对象（或者说是实例），使用者不能直接创建 `CFRunLoop` 对象，只能通过 `CFRunLoopGetCurrent` 和 `CFRunLoopGetMain` 函数来获得 `CFRunLoop` 对象。因为 `CFRunLoop` 是在一条程序流程（调用栈）上运行的，所以 `CFRunLoop` 对象是与线程绑定的。

因此 `CFRunLoopGetCurrent` 函数便是获取当前线程的 `CFRunLoop` 对象，如果不存在的话会则会创建一个。`CFRunLoopGetMain` 则是获取主线程的 `CFRunLoop` 对象。

使用 `CFRunLoopGetCurrent` 就可以开启当前线程的 run loop（也就是创建 `CFRunLoop` 对象），但是刚开启的 run loop 并不是处于运行状态的，需要使用者让 run loop 运行起来。在研究如何使 run loop 运行起来和 run loop 运行起来后的行为，需要先了解 run loop 的一些具体结构。

Run loop 需要处理四类事物：

1. Sources

    从名字可以可以看出，源，其实就是事件的来源。Sources 分为 sources 0 和 sources 1，其中 sources 1 是基于 mach port 也就是端口的，sources 0 则是需要手动触发的。统一被封装为 `CFRunLoopSource`。
    
2. Timers

    就是定时器，被封装为 `CFRunLoopTimer`。`NSTimer` 也是这个玩意（toll-free bridged）。
    
3. Observers

    这个严格来说并不是需要处理的事件，而是类似 notification 或者 delegate 一样的东西，run loop 会向 observers 汇报状态。被封装为 `CFRunLoopObserver`。
    
4. Blocks

    这个似乎在别的文章里没有被提到，从 macOS 10.6/iOS 4 开始，可以使用 `CFRunLoopPerformBlock` 函数往 run loop 中添加 blocks。
    
Run loop 还有一个很重要的东西叫做 run loop mode 或者称为模式，run loop 跑起来的时候需要指定一个特定的模式，**上面四种事物也都需要关联特定的模式**。模式起到了类似 fliter 一样的作用，`CFRunLoop` 提供了两个默认的模式：

1. `kCFRunLoopDefaultMode`
2. `kCFRunLoopCommonModes`

其中 `kCFRunLoopDefaultMode` 是创建 run loop 时同时创建的一个模式，可以称之为默认模式，没有特定要求的操作都可以扔到这个模式里。

`kCFRunLoopCommonModes` 其实并不是一个真正的模式，可以看到它是 `Modes` 而不是 `Mode`，是一个模式的集合：

- 使用 `CFRunLoopAddCommonMode` 函数将一个模式加入 common modes 集合
- 在添加 source，timer，observer 或者 block 的时候，如果指定的模式为 `kCFRunLoopCommonModes`，则会被分别添加到 common modes 集合中的所有模式中
- `kCFRunLoopDefaultMode` 默认是在 common modes 中的

关于 run loop mode 一个经典的例子就是 scroll view 滑动时会停止 timer，这就是因为 scroll view 在滑动时将 run loop mode 切换到 `UITrackingRunLoopMode`，而 timer 注册到了 `kCFRunLoopDefaultMode` 引起的。

## 运行 Run Loop

`CFRunLoop` 提供了两个函数用来使 run loop 运行起来：

```c
void CFRunLoopRun(void);

CFRunLoopRunResult 
CFRunLoopRunInMode(CFRunLoopMode mode, 
                   CFTimeInterval seconds, 
                   Boolean returnAfterSourceHandled);
```

`CFRunLoopRunInMode` 函数需要指定：

- `CFRunLoopMode mode`：一个 run loop mode
- `CFTimeInterval`：最多能运行多久（超时时间）
- `Boolean returnAfterSourceHandled`：处理一个事件后是否返回

这个函数明显对 run loop 的运行有很好的控制，可以想象 scroll view 滑动时就是靠调用这个函数来改变 run loop 的模式。因此 `CFRunLoop` 的使用和最开始提到的 event loop 的思想就有点不一样了，使用 `CFRunLoop` 的套路变成下面这样：

```c
int main(void) {
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    
    // 添加一些 source，timer，observer 或者 block
    
    while (message != 退出) {
        message = 获取消息();
        mode = // 处理消息看是否需要改变 mode，比如 scroll view 滑动
        time = // 设置一个超时时间
        CFRunLoopRunInMode(mode,
                           time,
                           true); // 猜测大部分时间为 true，因为需要更灵活的控制
    }
    return 0;
}
```

这样看来 `CFRunLoop` 只是 event loop 的一部分，主要用来实际的执行事件。当然，`CFRunLoop` 还提供了闲时睡眠功能来保证效率。

反过来看 `CFRunLoopRun` 函数，这个函数等同于在 `kCFRunLoopDefaultMode` 运行，可以运行无限久，处理了事件不需要返回而是继续运行。只能使用 `CFRunLoopStop` 函数或者将 run loop 里所有的事件来源（sources，timers，observers 和 blocks）移除来使 run loop 退出。因此官方文档并不推荐使用这个函数，但对于只做一件事情的线程来说，也可以使用这个函数，省去了 run loop 的外层循环（最典型的例子是 AFNetworking 中的那一例）。

## Run Loop 运行顺序

以下是启动 run loop 后比较关键的运行步骤：

1. 通知 observers: `kCFRunLoopEntry`, 进入 run loop
2. 通知 observers: `kCFRunLoopBeforeTimers`, 即将处理 timers
3. 通知 observers: `kCFRunLoopBeforeSources`, 即将处理 sources
4. 处理 blocks, 可以对 `__CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__` 函数下断点观察到
5. 处理 sources 0, 可以对 `__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__` 函数下断点观察到
6. 如果第 5 步实际处理了 sources 0，再一次处理 blocks
7. 如果在主线程，检查是否有 GCD 事件需要处理，有的话，跳转到第 11 步
8. 通知 observers: `kCFRunLoopBeforeWaiting`, 即将进入等待（睡眠）
9. 等待被唤醒，可以被 sources 1、timers、`CFRunLoopWakeUp` 函数和 GCD 事件（如果在主线程）
10. 通知 observers: `kCFRunLoopAfterWaiting`, 即停止等待（被唤醒）
11. 被什么唤醒就处理什么：
    - 被 timers 唤醒，处理 timers，可以在 `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__` 函数下断点观察到
    - 被 GCD 唤醒或者从第 7 步跳转过来的话，处理 GCD，可以在 `__CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__` 函数下断点观察到
    - 被 sources 1 唤醒，处理 sources 1，可以在 `__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE1_PERFORM_FUNCTION__` 函数下断点观察到
12. 再一次处理 blocks
13. 判断是否退出，不需要退出则跳转回第 2 步
14. 通知 observers: `kCFRunLoopExit`, 退出 run loop

有一点出入的地方是如果在第 5 步实际处理了 sources 0，是不会进入睡眠的。具体可以观看下面的源码注释。

## 关于 Apple 对 Run Loop 的应用

郭曜源大神的文章「[深入理解RunLoop](http://blog.ibireme.com/2015/05/18/runloop/)」和孙源大神的视频「[iOS线下分享《RunLoop》by 孙源@sunnyxx](http://v.youku.com/v_show/id_XODgxODkzODI0.html)」都对 Apple 如何使用 run loop 做了介绍。

个人探索推荐对下面几个函数下断点进行观察：

1. `__CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__`

    这是在 GCD 调用前的包装函数
    
2. `__CFRUNLOOP_IS_CALLING_OUT_TO_AN_OBSERVER_CALLBACK_FUNCTION__`

    这是在 observer 调用前的包装函数
    
3. `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__`

    这是在 timer 调用前的包装函数
    
4. `__CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__`

    这是在 block 调用前的包装函数
    
5. `__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__`

    这是在 source 0 调用前的包装函数
    
6. `__CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE1_PERFORM_FUNCTION__`

    这是在 source 1 调用前的包装函数

## 关于 Core Foundation 的源码

在 [Apple Open Source](https://opensource.apple.com/) 可以下载到的最新 CF 源码为 10.10.5 下的 CF-1153.18（2017 年 6 月 23 日），10.11 和 10.12 的 CF 源码都标注为「coming soon!」。

在 Apple Open Source 下载到的 CF 源码中有一个 README_CFLITE 文件，告诉了我们一个事实：

> What is CFLite?
> 
> CFLite is an open source version of the CoreFoundation framework found on Mac OS X and iOS. It is designed to be simple and portable. For example, it can be used on other platforms to read and write property lists that may come from Mac OS X or iOS.
>
> It is important to note that this version is not the exact same version as is used on Mac OS X or iOS, but they do share a significant amount of code.

所以在 [Apple Open Source](https://opensource.apple.com/) 下载到的其实是 CFLite，是开源版的 Core Foundation，和系统中带的并不是完全一模一样的。

但是现在还有另外一个版本，就是使用 Swift 实现的 Foundation 框架，开源在 GitHub: [swift-corelibs-foundation](https://github.com/apple/swift-corelibs-foundation), 其中也包含了 Core Foundation。当然，这个版本肯定跟系统里的版本也是不一样的。

我猜测这里的 Core Foundation 版本和 Apple Open Source 这个网站的版本是一样的，只不过更新，比如最近的 commit：「Import CoreFoundation changes from Sierra」，表明已经是 Sierra 的版本了。

本文使用的源码是 [swift-corelibs-foundation](https://github.com/apple/swift-corelibs-foundation) master 分支上的版本。

## 源码注释

### 数据结构

#### Run Loop

```c
typedef struct CF_BRIDGED_MUTABLE_TYPE(id) __CFRunLoop * CFRunLoopRef;

struct __CFRunLoop {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;			/* locked for accessing mode list */
    __CFPort _wakeUpPort;			// used for CFRunLoopWakeUp 
    Boolean _unused;
    volatile _per_run_data *_perRunData;              // reset for runs of the run loop
    pthread_t _pthread;
    uint32_t _winthread;
    CFMutableSetRef _commonModes;
    CFMutableSetRef _commonModeItems;
    CFRunLoopModeRef _currentMode;
    CFMutableSetRef _modes;
    struct _block_item *_blocks_head;
    struct _block_item *_blocks_tail;
    CFAbsoluteTime _runTime;
    CFAbsoluteTime _sleepTime;
    CFTypeRef _counterpart;
};
```

类型 | 变量名 | 用处
--- | --- | ---
`CFRuntimeBase` | `_base` | 应该是 Core Foundation 对象都需要的东西
`pthread_mutex_t` | `_lock` | 一个 mutex，根据注释，是用来锁对于 mode 的访问的。对其操作由 `__CFRunLoopLockInit`、`__CFRunLoopLock` 和 `__CFRunLoopUnlock` 函数封装
`__CFPort` | `_wakeUpPort` | `__CFPort` 实际上就是 `mach_port_t`。根据注释，这是用来唤醒 run loop 的 mach port，被 `CFRunLoopWakeUp` 函数使用
`Boolean` | `_unused` | 和变量名一样，没有使用的变量，猜测是为了对齐用？
`_per_run_data *` | `_perRunData` | 每次调用 `CFRunLoopRun` 或者 `CFRunLoopRunInMode` 函数（实际就是对 `CFRunLoopRunSpecific` 函数的调用），也就是每次 run 的一个独立数据。相关操作：`__CFRunLoopPushPerRunData` 和 `__CFRunLoopPopPerRunData`，这个又 push 又 pop 的原因是因为 run loop 可以嵌套调用
`pthread_t` | `_pthread` | 对应的 pthread
`uint32_t` | `_winthread` | Windows 下对应线程
`CFMutableSetRef` | `_commonModes` | 存放 common mode 的集合
`CFMutableSetRef` | `_commonModeItems` | 每个 common mode 都有的 item (source, timer and observer) 集合
`CFRunLoopModeRef` | `_currentMode` | 当前 run 的 mode
`CFMutableSetRef` | `_modes` | 这个 run loop 所有的 mode 集合
`sturct _block_item *` | `_blocks_head` | 存放 `CFRunLoopPerformBlock` 函数添加的 block 的双向链表的头指针
`sturct _block_item *` | `_blocks_tail` | 同上尾脂针
`CFAbsoluteTime` | `_runTime` | 估计是一共跑着的时间（但实际上根本没使用）
`CFAbsoluteTime` | `_sleepTime` | 一共睡了多久
`CFTypeRef` | `_counterpart` | 给 Swift 用的玩意

#### Run Loop Mode

```c
typedef struct __CFRunLoopMode *CFRunLoopModeRef;

struct __CFRunLoopMode {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;	/* must have the run loop locked before locking this */
    CFStringRef _name;
    Boolean _stopped;
    char _padding[3];
    CFMutableSetRef _sources0;
    CFMutableSetRef _sources1;
    CFMutableArrayRef _observers;
    CFMutableArrayRef _timers;
    CFMutableDictionaryRef _portToV1SourceMap;
    __CFPortSet _portSet;
    CFIndex _observerMask;
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    dispatch_source_t _timerSource;
    dispatch_queue_t _queue;
    Boolean _timerFired; // set to true by the source when a timer has fired
    Boolean _dispatchTimerArmed;
#endif
#if USE_MK_TIMER_TOO
    __CFPort _timerPort;
    Boolean _mkTimerArmed;
#endif
#if DEPLOYMENT_TARGET_WINDOWS
    DWORD _msgQMask;
    void (*_msgPump)(void);
#endif
    uint64_t _timerSoftDeadline; /* TSR */
    uint64_t _timerHardDeadline; /* TSR */
};
```

`USE_DISPATCH_SOURCE_FOR_TIMERS` 这个宏的值为 1，也就是说有使用 GCD 来实现 timer，当然 `USE_MK_TIMER_TOO` 这个宏的值也是 1，表示**也**使用了更底层的 timer。

类型 | 变量名 | 用处
--- | --- | --- 
`CFRuntimeBase` | `_base` | 应该是 Core Foundation 对象都需要的东西
`pthread_mutex_t` | `_lock` | 一个 mutex，锁 mode 里的各种操作。根据注释，需要 run loop 的锁先锁上才能锁这个锁。同样也有两个函数 `__CFRunLoopModeLock` 和 `__CFRunLoopModeUnlock` 对其操作进行了简单封装
`CFStringRef` | `_name` | 当然是名字啦
`Boolean` | `_stopped` | 是否停止了
`char[3]` | `_padding` | 可能是为了对齐用的吧……
`CFMutableSetRef` | `_sources0` | Source0 集合，也就是非 port 的 source
`CFMutableSetRef` | `_sources1` | Source1 集合，也就是基于 port 的 source
`CFMutableArrayRef` | `_observers` | Observer 集合
`CFMutableArrayRef` | `_timers` | Timer 集合
`CFMutableDictionaryRef` | `_portToV1SourceMap` | Key 是 port，value 是对应 source1 的字典
`__CFPortSet` | `_portSet` | 所有 port 的集合
`CFIndex` | `_observerMask` | 需要 observe 的事件的 mask，一个小优化
`dispatch_source_t` | `_timerSource` | 用来实现 timer 的 GCD timer
`dispatch_queue_t` | `_queue` | 放 `_timerSource` 的队列
`Boolean` | `_timerFired` | `_timerSource` 是否被启动
`Boolean` | `_dispatchTimerArmed` | timer 是否被安装上了，或者说是否开启了
`__CFPort` | `_timerPort` | 使用 MK timer 时的端口
`Boolean` | `_mkTimerArmed` | timer 是否被开启
`uint64_t` | `_timerSoftDeadline` | 下一个计划启动的时间
`uint64_t` | `_timerHardDeadline` | 下一个最迟启动的时间（计划加上容忍延迟的时间）

### 运行函数

```c
void CFRunLoopRun(void) {	/* DOES CALLOUT */
    int32_t result;
    do {
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), 
                                      kCFRunLoopDefaultMode, 
                                      1.0e10, 
                                      false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result 
             && kCFRunLoopRunFinished != result);
}

SInt32 
CFRunLoopRunInMode(CFStringRef modeName, 
                   CFTimeInterval seconds, 
                   Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    return CFRunLoopRunSpecific(CFRunLoopGetCurrent(), 
                                modeName, 
                                seconds, 
                                returnAfterSourceHandled);
}
```

可以看到 `CFRunLoopRun` 函数不主动调用 `CFRunLoopStop` 函数（`kCFRunLoopRunStopped` 的情况）或者将所有事件源移除（`kCFRunLoopRunFinished` 的情况）是没有办法退出的。

```c
SInt32 
CFRunLoopRunSpecific(CFRunLoopRef rl, 
                     CFStringRef modeName, 
                     CFTimeInterval seconds, 
                     Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    //// 检查 mode 是否合法
    if (modeName == NULL || modeName == kCFRunLoopCommonModes || CFEqual(modeName, kCFRunLoopCommonModes)) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            CFLog(kCFLogLevelError, CFSTR("invalid mode '%@' provided to CFRunLoopRunSpecific - break on _CFRunLoopError_RunCalledWithInvalidMode to debug. This message will only appear once per execution."), modeName);
            _CFRunLoopError_RunCalledWithInvalidMode();
        });
        return kCFRunLoopRunFinished;
    }
    //// 检查 run loop 是否正在销毁
    if (__CFRunLoopIsDeallocating(rl)) return kCFRunLoopRunFinished;
    __CFRunLoopLock(rl);
    //// 查找 modeName 指定的 mode
    CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
    //// 没有找到 mode 或者 mode 里面没有任何事件源的话，返回 kCFRunLoopRunFinished
    if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
        //// 不能理解这个 did 有什么用……
        Boolean did = false;
        if (currentMode) __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopUnlock(rl);
        return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
    }
    //// 因为可以嵌套调用，保存一下之前的状态
    volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
    CFRunLoopModeRef previousMode = rl->_currentMode;
    //// 初始化当前调用的状态
    rl->_currentMode = currentMode;
    int32_t result = kCFRunLoopRunFinished;

    //// 1. 通知 observers: kCFRunLoopEntry, 进入 run loop
    if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
    result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
    //// 14. 通知 observers: `kCFRunLoopExit`, 退出 run loop
    if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);

    //// 恢复之前的状态
    __CFRunLoopModeUnlock(currentMode);
    __CFRunLoopPopPerRunData(rl, previousPerRun);
    rl->_currentMode = previousMode;
    __CFRunLoopUnlock(rl);
    return result;
}
```

接下来的代码中删除了关于 Windows 和 Linux 的源码：

```c
/* rl, rlm are locked on entrance and exit */
static int32_t
__CFRunLoopRun(CFRunLoopRef rl,
               CFRunLoopModeRef rlm,
               CFTimeInterval seconds,
               Boolean stopAfterHandle,
               CFRunLoopModeRef previousMode)
{
    //// 记录开始时间
    uint64_t startTSR = mach_absolute_time();
    
    //// 检查是否被停止
    if (__CFRunLoopIsStopped(rl)) {
        __CFRunLoopUnsetStopped(rl);
        return kCFRunLoopRunStopped;
    } else if (rlm->_stopped) {
        rlm->_stopped = false;
        return kCFRunLoopRunStopped;
    }

    //// 如果使用了 GCD 的话，获取 GCD 消息端口
#if __HAS_DISPATCH__
    //// GCD 端口存放变量
    __CFPort dispatchPort = CFPORT_NULL;
    //// 检查是否在主线程（和是否允许嵌套调用的 run loop 处理 GCD）
    Boolean libdispatchQSafe =
    pthread_main_np()
    && ((HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && NULL == previousMode)
        || (!HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && 0 == _CFGetTSD(__CFTSDKeyIsInGCDMainQ)));
    //// 需要在主线程，run loop 也是主线程的 run loop，并且 mode 是 common mode
    if (libdispatchQSafe
        && (CFRunLoopGetMain() == rl)
        && CFSetContainsValue(rl->_commonModes, rlm->_name))
        //// 从 GCD 的私有 API 获取端口（4CF 表示 for Core Foundation）
        dispatchPort = _dispatch_get_main_queue_port_4CF();
#endif

    //// 如果使用 GCD timer 作为 timer 的实现的话，进行准备工作
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    mach_port_name_t modeQueuePort = MACH_PORT_NULL;
    if (rlm->_queue) {
        modeQueuePort = _dispatch_runloop_root_queue_get_port_4CF(rlm->_queue);
        if (!modeQueuePort) {
            CRASH("Unable to get port for run loop mode queue (%d)", -1);
        }
    }
#endif

    //// 设置超时的玩意开始
#if __HAS_DISPATCH__
    dispatch_source_t timeout_timer = NULL;
#endif
    struct __timeout_context *timeout_context = (struct __timeout_context *)malloc(sizeof(*timeout_context));
    if (seconds <= 0.0) { // instant timeout
        seconds = 0.0;
        timeout_context->termTSR = 0ULL;
    } else if (seconds <= TIMER_INTERVAL_LIMIT) {
#if __HAS_DISPATCH__
        dispatch_queue_t queue = 
        pthread_main_np() 
        ? __CFDispatchQueueGetGenericMatchingMain() 
        : __CFDispatchQueueGetGenericBackground();
        timeout_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 
                                               0, 
                                               0, 
                                               queue);
        dispatch_retain(timeout_timer);
        timeout_context->ds = timeout_timer;
#endif
        timeout_context->rl = (CFRunLoopRef)CFRetain(rl);
        timeout_context->termTSR = startTSR + __CFTimeIntervalToTSR(seconds);
#if __HAS_DISPATCH__
        dispatch_set_context(timeout_timer, timeout_context); // source gets ownership of context
        dispatch_source_set_event_handler_f(timeout_timer, __CFRunLoopTimeout);
        dispatch_source_set_cancel_handler_f(timeout_timer, __CFRunLoopTimeoutCancel);
        uint64_t ns_at = (uint64_t)((__CFTSRToTimeInterval(startTSR) + seconds) * 1000000000ULL);
        dispatch_source_set_timer(timeout_timer, dispatch_time(1, ns_at), DISPATCH_TIME_FOREVER, 1000ULL);
        dispatch_resume(timeout_timer);
#endif
    } else { // infinite timeout
        seconds = 9999999999.0;
        timeout_context->termTSR = UINT64_MAX;
    }
    //// 设置超时的玩意结束

    Boolean didDispatchPortLastTime = true;
    int32_t retVal = 0;
    do {
        voucher_mach_msg_state_t voucherState = VOUCHER_MACH_MSG_STATE_UNCHANGED;
        voucher_t voucherCopy = NULL;
        
        uint8_t msg_buffer[3 * 1024];

        mach_msg_header_t *msg = NULL;
        mach_port_t livePort = MACH_PORT_NULL;

        __CFPortSet waitSet = rlm->_portSet;

        __CFRunLoopUnsetIgnoreWakeUps(rl);
        
        //// 2. 通知 observers: kCFRunLoopBeforeTimers, 即将处理 timers
        if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
        //// 3. 通知 observers: kCFRunLoopBeforeSources, 即将处理 sources
        if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);

        //// 4. 处理 blocks
        __CFRunLoopDoBlocks(rl, rlm);
        
        //// 5. 处理 sources 0
        Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
        //// 6. 如果第 5 步实际处理了 sources 0，再一次处理 blocks
        if (sourceHandledThisLoop) {
            __CFRunLoopDoBlocks(rl, rlm);
        }
        
        //// 是否处理过 source 或超时
        Boolean poll = sourceHandledThisLoop 
                       || (0ULL == timeout_context->termTSR);

        //// 7. 如果在主线程，检查是否有 GCD 事件需要处理，有的话，跳转到第 11 步
#if __HAS_DISPATCH__
        if (MACH_PORT_NULL != dispatchPort 
            && !didDispatchPortLastTime) {
            msg = (mach_msg_header_t *)msg_buffer;
            //// __CFRunLoopServiceMachPort 这个函数会睡眠线程，如果超时时间不为 0 的话
            if (__CFRunLoopServiceMachPort(dispatchPort,       // 监听的端口 
                                           &msg,               // 存放消息的地址
                                           sizeof(msg_buffer),
                                           &livePort,          // 返回发送消息的端口
                                           0,                  // 超时时间，这里为 0 表示不会睡眠 
                                           &voucherState, 
                                           NULL)) {
                goto handle_msg;
            }
        }
#endif

        didDispatchPortLastTime = false;
        
        //// 8. 通知 observers: kCFRunLoopBeforeWaiting, 即将进入等待（睡眠）
        //// 注意到如果实际处理了 source 0 或者超时了，不会进入睡眠，所以不会通知
        if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
        //// 设置标志位，正在睡眠（实际上没有开始睡）
        __CFRunLoopSetSleeping(rl);
        // do not do any user callouts after this point (after notifying of sleeping)

        // Must push the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced.
#if __HAS_DISPATCH__
        //// 使用 GCD 的话，将 GCD 端口加入所有监听端口集合中
        __CFPortSetInsert(dispatchPort, waitSet);
#endif

        __CFRunLoopModeUnlock(rlm);
        __CFRunLoopUnlock(rl);

        //// 记录睡眠开始时间
        CFAbsoluteTime sleepStart = poll ? 0.0 : CFAbsoluteTimeGetCurrent();

        //// 9. 等待被唤醒，可以被 sources 1、timers、CFRunLoopWakeUp 函数和 GCD 事件（如果在主线程）
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        //// 使用 GCD timer 作为 timer 实现的情况
        do {
            msg = (mach_msg_header_t *)msg_buffer;
            
            //// 这个函数会睡眠线程
            __CFRunLoopServiceMachPort(waitSet, // 监听端口集合    
                                       &msg, 
                                       sizeof(msg_buffer), 
                                       &livePort, // 返回收到消息的端口
                                       poll ? 0 : TIMEOUT_INFINITY, // 根据状态睡眠或者不睡
                                       &voucherState, 
                                       &voucherCopy);

            //// 如果是 timer 端口唤醒的，进行一下善后处理，之后再处理 timer
            if (modeQueuePort != MACH_PORT_NULL 
                && livePort == modeQueuePort) {
                // Drain the internal queue. If one of the callout blocks sets the timerFired flag, break out and service the timer.
                while (_dispatch_runloop_root_queue_perform_4CF(rlm->_queue))
                    ;
                if (rlm->_timerFired) {
                    // Leave livePort as the queue port, and service timers below
                    rlm->_timerFired = false;
                    break;
                } else {
                    if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
                }
            } else {
            //// 不是 timer 端口唤醒的，进行接下来的处理
                // Go ahead and leave the inner loop.
                break;
            }
        } while (1);
#else
        ///// 不使用 GCD timer 作为 timer 实现的情况
        msg = (mach_msg_header_t *)msg_buffer;
        __CFRunLoopServiceMachPort(waitSet, 
                                   &msg, 
                                   sizeof(msg_buffer), 
                                   &livePort, 
                                   poll ? 0 : TIMEOUT_INFINITY, 
                                   &voucherState, 
                                   &voucherCopy);
#endif

        __CFRunLoopLock(rl);
        __CFRunLoopModeLock(rlm);

        //// 增加记录的睡眠时间
        rl->_sleepTime += (poll ? 0.0 : (CFAbsoluteTimeGetCurrent() - sleepStart));

        // Must remove the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced. Also, we don't want them left
        // in there if this function returns.
#if __HAS_DISPATCH__
        //// 将 GCD 端口移除
        __CFPortSetRemove(dispatchPort, waitSet);
#endif

        __CFRunLoopSetIgnoreWakeUps(rl);

        // user callouts now OK again
        __CFRunLoopUnsetSleeping(rl);
        //// 10. 通知 observers: kCFRunLoopAfterWaiting, 即停止等待（被唤醒）
        //// 注意实际处理过 source 0 或者已经超时的话，不会通知（因为没有睡）
        if (!poll && (rlm->_observerMask & kCFRunLoopAfterWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);

        //// 11. 被什么唤醒就处理什么：
    handle_msg:;
        __CFRunLoopSetIgnoreWakeUps(rl);

        if (MACH_PORT_NULL == livePort) {
            //// 不知道哪个端口唤醒的（或者根本没睡），啥也不干
            CFRUNLOOP_WAKEUP_FOR_NOTHING();
            // handle nothing
        } else if (livePort == rl->_wakeUpPort) {
            //// 被 CFRunLoopWakeUp 函数弄醒的，啥也不干
            CFRUNLOOP_WAKEUP_FOR_WAKEUP();
            // do nothing on Mac OS
        }
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        else if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
            //// 被 timers 唤醒，处理 timers
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer, because we apparently fired early
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
#if USE_MK_TIMER_TOO
        else if (rlm->_timerPort != MACH_PORT_NULL && livePort == rlm->_timerPort) {
            //// 被 timers 唤醒，处理 timers
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            // On Windows, we have observed an issue where the timer port is set before the time which we requested it to be set. For example, we set the fire time to be TSR 167646765860, but it is actually observed firing at TSR 167646764145, which is 1715 ticks early. The result is that, when __CFRunLoopDoTimers checks to see if any of the run loop timers should be firing, it appears to be 'too early' for the next timer, and no timers are handled.
            // In this case, the timer port has been automatically reset (since it was returned from MsgWaitForMultipleObjectsEx), and if we do not re-arm it, then no timers will ever be serviced again unless something adjusts the timer list (e.g. adding or removing timers). The fix for the issue is to reset the timer here if CFRunLoopDoTimers did not handle a timer itself. 9308754
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
#if __HAS_DISPATCH__
        else if (livePort == dispatchPort) {
            //// 被 GCD 唤醒或者从第 7 步跳转过来的话，处理 GCD
            CFRUNLOOP_WAKEUP_FOR_DISPATCH();
            __CFRunLoopModeUnlock(rlm);
            __CFRunLoopUnlock(rl);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)6, NULL);
            __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__(msg);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)0, NULL);
            __CFRunLoopLock(rl);
            __CFRunLoopModeLock(rlm);
            sourceHandledThisLoop = true;
            didDispatchPortLastTime = true;
        }
#endif
        else {
            //// 被 sources 1 唤醒，处理 sources 1
            CFRUNLOOP_WAKEUP_FOR_SOURCE();
            // Despite the name, this works for windows handles as well
            CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
            if (rls) {
                mach_msg_header_t *reply = NULL;
                sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
                if (NULL != reply) {
                    (void)mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
                    CFAllocatorDeallocate(kCFAllocatorSystemDefault, reply);
                }
            }

        }

        if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);

        //// 12. 再一次处理 blocks
        __CFRunLoopDoBlocks(rl, rlm);

        //// 13. 判断是否退出，不需要退出则跳转回第 2 步
        if (sourceHandledThisLoop && stopAfterHandle) {
            retVal = kCFRunLoopRunHandledSource;
        } else if (timeout_context->termTSR < mach_absolute_time()) {
            retVal = kCFRunLoopRunTimedOut;
        } else if (__CFRunLoopIsStopped(rl)) {
            __CFRunLoopUnsetStopped(rl);
            retVal = kCFRunLoopRunStopped;
        } else if (rlm->_stopped) {
            rlm->_stopped = false;
            retVal = kCFRunLoopRunStopped;
        } else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
            retVal = kCFRunLoopRunFinished;
        }
        
    } while (0 == retVal);
#if __HAS_DISPATCH__
    if (timeout_timer) {
        dispatch_source_cancel(timeout_timer);
        dispatch_release(timeout_timer);
    } else
#endif
    {
        free(timeout_context);
    }
    
    return retVal;
}
```

## 参考

- [Threading Programming Guide: Run Loops](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/Multithreading/RunLoopManagement/RunLoopManagement.html)
- [深入理解RunLoop](http://blog.ibireme.com/2015/05/18/runloop/)
- [iOS线下分享《RunLoop》by 孙源@sunnyxx](http://v.youku.com/v_show/id_XODgxODkzODI0.html)
- [swift-corelibs-foundation](https://github.com/apple/swift-corelibs-foundation)
