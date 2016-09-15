> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/SDWebImage2/)

# SDWebImage Source Probe: Manager

在 *[SDWebImage Source Probe: WebCache](https://github.com/Desgard/iOS-Source-Probe/blob/master/Objective-C/SDWebImage/SDWebImage%20Source%20Probe%20-%20WebCache.md)* 一文中，通过最常用的 `sd_setImageWithURL` 方法，来分析源码。而在其中，对于图片的 download 方法，也是需要理解的重点之一。它用于处理异步下载和图片缓存的类，当然也可直接拿来使用。`SDWebImageManager` 这个类，为 `WebCache` 、 `SDWebImageDownloader` 和 `SDImageCache` 搭建了一个桥梁，使得拥有更好的协同性。而每个类负责的功能不同，又是通过该类进行了结构上的解耦。

这篇通过分析 `SDWebImageManager` 的 Source Code ，来深入分析一下 SD 三方库中，对于 download 方法具体实现细节。

## download 策略一览

在 WebCache 的 sd_setImageWithURL 方法中的 download 策略，调用了这个方法：

```c
- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url
                                         options:(SDWebImageOptions)options
                                        progress:(SDWebImageDownloaderProgressBlock)progressBlock
                                       completed:(SDWebImageCompletionWithFinishedBlock)completedBlock;
```

参数解释：

* **url**：image 对应的 url
* **options**：缓存策略枚举
* **progress**：在 download 过程中的动作，block 实现
* **completed**：在 download 完成后的动作，block 实现

在查看方法之前，先来查看一下缓存策略枚举（options）是如何定义的，在源码中作者已经在注释里描述了每一种枚举代表的含义，这里笔者翻译了一下：

```c
typedef NS_OPTIONS(NSUInteger, SDWebImageOptions) {
    // 下载失败后会继续尝试下载
    SDWebImageRetryFailed = 1 << 0,

    // 当正在进行 UI 交互时，自动暂停内部的一些下载操作
    // 一种延迟下载策略。比如在 UIScrollView 快速滑动的时候暂停下载
    // 但是当滑动速度减慢时，下载开始
    SDWebImageLowPriority = 1 << 1,

    // 只进行内存缓存，不缓存到硬盘
    SDWebImageCacheMemoryOnly = 1 << 2,

    // 渐进式下载模式
    // 图像会像 brower 一样，一点点加载出来
    SDWebImageProgressiveDownload = 1 << 3,

    // 刷新缓存
    // 将硬盘缓存交给硬盘自带的 NSURLCache 处理
    // 当同一个 URL 对应的图片频繁改变的时候，可以使用该策略
    SDWebImageRefreshCached = 1 << 4,
    
    // 后台下载，试用与 iOS 4+ 系统中
    SDWebImageContinueInBackground = 1 << 5,

    // 设置 NSMutableURLRequest.HTTPShouldHandleCookies = YES;
    // 从而来处理存储在 NSHTTPCookieStore 的 cookie
    SDWebImageHandleCookies = 1 << 6,

    // 允许无效的 SSL 检验
    SDWebImageAllowInvalidSSLCertificates = 1 << 7,

    // 使用高级别的线程权限，默认是等待当前线程完成再进行
    SDWebImageHighPriority = 1 << 8,
    
    // 默认情况向，当网络图片加载时占位图片（place holder）显示。
    // 若采用此策略，则不会显示占位图片，直到网络图片加载完成后，如果失败则使用占位图片
    SDWebImageDelayPlaceholder = 1 << 9,

    // 是否 transform 图片
    // 常作为 transformdownloadedimage 代理方法的替代
    // 防止对图片解析时的破坏
    SDWebImageTransformAnimatedImage = 1 << 10,
    
    // 下载完成后，手动设置图片
    // 一般默认情况下，下载完成会自动加载到 ImageView 上
    SDWebImageAvoidAutoSetImage = 1 << 11
};
```

## Manage Download Image 主要流程

了解了所有的下载策略，开始阅读实现的源码。


```c
if ([url isKindOfClass:NSString.class]) {
   url = [NSURL URLWithString:(NSString *)url];
}
```

首先，先考虑到了传递参数 url 类型为 NSString 的情况，在注释中，作者这样写道：

> 没有传递 NSURL ，而是使用 NSString 对象传递 url 是一个很常见的错误。由于一些奇怪的原因，Xcode 并不会抛出类型不匹配的警告。所以，我们于此允许传递 NSString 对象，并自动转换成 NSURL 从而保护该错误。

```c
if (![url isKindOfClass:NSURL.class]) {
   url = nil;
}
```

仍是为了防止参数类型错误，对 url 的类型再次进行了判断。如果非法，则赋 nil 方便后面的排查。

```c
__block SDWebImageCombinedOperation *operation = [SDWebImageCombinedOperation new];
__weak SDWebImageCombinedOperation *weakOperation = operation;
```

当 url 合法性过滤过程完成后，发现了源码中会实例化 `SDWebImageCombinedOperation` 这么一个对象。这是继承与 `NSObject` 并遵循 `SDWebImageOperation` 协议的一个类。

### SDWebImageCombinedOperation

```c
// SDWebImageOperation.h
// 协议声明
@protocol SDWebImageOperation <NSObject>

- (void)cancel;

@end
```

这个协议十分简单，仅仅声明了一个 `cancel` 方法。这里会自然而然的想起 `NSOperation` 。`NSOperation` 在处理事件中，会提供一个 cancel 方法可以取消当前的操作。其实，调用这个 cancel 方法，会将 `SDWebImageCombinedOperation` 持有的 `cacheOperation` （NSOperation） 和 cancelBlock （block） 给 cancel 掉。代码如下：

```c
// SDWebImageCombinedOperation
// cancel #1

- (void)cancel {
    self.cancelled = YES;
    if (self.cacheOperation) {
        [self.cacheOperation cancel];
        self.cacheOperation = nil;
    }
    if (self.cancelBlock) {
        self.cancelBlock();
        _cancelBlock = nil;
    }
}
```

这个也能体现出 SD 库的简洁接口性。大概了解了代理方法 cancel 在这里的实现，下面来看一下 SDWebImageCombinedOperation 的声明。

```c
@interface SDWebImageCombinedOperation : NSObject <SDWebImageOperation>

@property (assign, nonatomic, getter = isCancelled) BOOL cancelled;
@property (copy, nonatomic) SDWebImageNoParamsBlock cancelBlock;
@property (strong, nonatomic) NSOperation *cacheOperation;

@end
```

在了解过 SDWebImageCombinedOperation 返回我们的 download 方法中，继续阅读代码。

```c
// 初始化标记，判断是否为下载失败的 url
BOOL isFailedUrl = NO;

// 对 failedURLs 的 getter 方法加互斥锁
@synchronized (self.failedURLs) {
	// 更新标记状态
   isFailedUrl = [self.failedURLs containsObject:url];
}

// 判断 url 是否为空串；是否下载策略为重新尝试下载且 url 为失效 url。
// 两者满足其一进入处理
if (url.absoluteString.length == 0 || (!(options & SDWebImageRetryFailed) && isFailedUrl)) {
	// 在 SDWebImageCompat.h 中定义的宏
	// 为了安全的跳至主线程上操作
   dispatch_main_sync_safe(^{
   	   // 创建对应问题的 error 对象
       NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil];
       // 向 completionBlock 中传参，结束 download 方法 
       completedBlock(nil, error, SDImageCacheTypeNone, YES, url);
   });
   return operation;
}
```

注意到两个问题，第一个是互斥锁 `@synchronized` 。我们知道，在 Foundation 框架中的 Mutable 可变基础类，都是非线程安全的。这里为了避免多线程对于 failedURLs 的篡改，所以对 failedURLs 的 getter 方法执行加锁操作。

## dispatch_main_sync_safe

对于宏 `dispatch_main_sync_safe` ，需要读一下它的实现。

```c
#define dispatch_main_sync_safe(block)\
    if ([NSThread isMainThread]) {\
        block();\
    } else {\
        dispatch_sync(dispatch_get_main_queue(), block);\
    }
```

很简单，其实就是将传入的 block 同步加载到主线程中。对应的，在这个宏下面还有一个 “安全异步 block 宏”，其道理和上述宏是一样的：

```c
#define dispatch_main_async_safe(block)\
    if ([NSThread isMainThread]) {\
        block();\
    } else {\
        dispatch_async(dispatch_get_main_queue(), block);\
    }
```

下面来看最长的一部分：

```c
@synchronized (self.runningOperations) {
   // 将 operation 加入到处理列表中
   [self.runningOperations addObject:operation];
}
// 获取缓存 key
NSString *key = [self cacheKeyForURL:url];
    
// 在缓存中通过 key 进行查找，结束后回调 done block
// 该方法在本系列下一篇文中会详细介绍
operation.cacheOperation = [self.imageCache queryDiskCacheForKey:key done:^(UIImage *image, SDImageCacheType cacheType) {
   // 判断该 operation 是否已经被 cancel
   if (operation.isCancelled) {
       // 如果为真，从处理列表中删除 operation
       @synchronized (self.runningOperations) {
           [self.runningOperations removeObject:operation];
       }
       
       return;
   }
   // 当 callback 参数中的 image 无效
   if ((!image || options & SDWebImageRefreshCached) && (![self.delegate respondsToSelector:@selector(imageManager:shouldDownloadImageForURL:)] || [self.delegate imageManager:self shouldDownloadImageForURL:url])) {
       if (image && options & SDWebImageRefreshCached) {
           dispatch_main_sync_safe(^{
               // 在 SDWebImageRefreshCached 策略下，即使在缓存中获取到图片，则需要通知缓存
               // 并重新尝试下载，使得 NSURLCache 刷新
               completedBlock(image, nil, cacheType, YES, url);
           });
       }
       
       // 如果没有图片或者被请求刷新，则开始下载操作
       // 通过缓存策略，从而确定下载策略
       // 下载策略下文会详细总结
       SDWebImageDownloaderOptions downloaderOptions = 0;
       // 如果缓存策略为 SDWebImageLowPriority 活动减慢开始策略
       // 下载策略为 SDWebImageDownloaderLowPriority 默认模式
       if (options & SDWebImageLowPriority) downloaderOptions |= SDWebImageDownloaderLowPriority;
       // 如果缓存策略为 SDWebImageDownloaderLowPriority 渐进式策略
       // 下载策略为 SDWebImageDownloaderProgressiveDownload 渐进式下载策略
       if (options & SDWebImageProgressiveDownload) downloaderOptions |= SDWebImageDownloaderProgressiveDownload;
       // 如果缓存策略为 SDWebImageRefreshCached 刷新缓存策略
       // 下载策略为 SDWebImageDownloaderUseNSURLCache 不使用 Cache 方式
       if (options & SDWebImageRefreshCached) downloaderOptions |= SDWebImageDownloaderUseNSURLCache;
       // 如果缓存策略为 SDWebImageContinueInBackground 后台下载策略
       // 下载策略为 SDWebImageDownloaderContinueInBackground 后台加载(iOS 4+)
       if (options & SDWebImageContinueInBackground) downloaderOptions |= SDWebImageDownloaderContinueInBackground;
       // 如果缓存策略为 SDWebImageHandleCookies Cookie 策略
       // 下载策略为 SDWebImageDownloaderHandleCookies 使用 NSHTTPCookieStore 存储 cookie 策略
       if (options & SDWebImageHandleCookies) downloaderOptions |= SDWebImageDownloaderHandleCookies;
       // 如果缓存策略为 SDWebImageAllowInvalidSSLCertificates 允许无效的 SSL 验证策略
       // 下载策略为 SDWebImageDownloaderAllowInvalidSSLCertificates 允许不受信任的SSL证书(常测试用)
       if (options & SDWebImageAllowInvalidSSLCertificates) downloaderOptions |= SDWebImageDownloaderAllowInvalidSSLCertificates;
       // 如果缓存策略为 SDWebImageHighPriority 高级别的线程权限策略
       // 则下载策略为 SDWebImageDownloaderHighPriority 将图片下载放到高优先级队列中策略
       if (options & SDWebImageHighPriority) downloaderOptions |= SDWebImageDownloaderHighPriority;
       // 如果使用的是刷新缓存策略
       if (image && options & SDWebImageRefreshCached) {
           // 强制解除渐进式下载策略
           downloaderOptions &= ~SDWebImageDownloaderProgressiveDownload;
           // 忽略缓存结果，强制刷新
           downloaderOptions |= SDWebImageDownloaderIgnoreCachedResponse;
       }
       // 进行下载图片
       id <SDWebImageOperation> subOperation = [self.imageDownloader downloadImageWithURL:url options:downloaderOptions progress:progressBlock completed:^(UIImage *downloadedImage, NSData *data, NSError *error, BOOL finished) {
           __strong __typeof(weakOperation) strongOperation = weakOperation;
           if (!strongOperation || strongOperation.isCancelled) {
               // 如果 operation 被取消，则不进行任何操作
               // 如果我们调用 completedBlock，可能会使得 completedBlock 和此 block 产生选择竞争，如果对其进行二次访问，则会重写
           }
           else if (error) {
               // 错误情况下，直接对 completedBlock 进行同步调用
               dispatch_main_sync_safe(^{
                   if (strongOperation && !strongOperation.isCancelled) {
                       completedBlock(nil, error, SDImageCacheTypeNone, finished, url);
                   }
               });
               // 错误来源不是非 url 无效造成的，则将 url 归类为无效 url 并缓存起来
               if (   error.code != NSURLErrorNotConnectedToInternet
                   && error.code != NSURLErrorCancelled
                   && error.code != NSURLErrorTimedOut
                   && error.code != NSURLErrorInternationalRoamingOff
                   && error.code != NSURLErrorDataNotAllowed
                   && error.code != NSURLErrorCannotFindHost
                   && error.code != NSURLErrorCannotConnectToHost) {
                   @synchronized (self.failedURLs) {
                       [self.failedURLs addObject:url];
                   }
               }
           }
           else {
               // 如果缓存策略选用了刷新缓存的话，从失效 url 表中移除
               if ((options & SDWebImageRetryFailed)) {
                   @synchronized (self.failedURLs) {
                       [self.failedURLs removeObject:url];
                   }
               }
               
               // 查看是否使用了 仅内存存储 策略
               BOOL cacheOnDisk = !(options & SDWebImageCacheMemoryOnly);
               
               if (options & SDWebImageRefreshCached && image && !downloadedImage) {
                   //  NSURLCache 刷新缓存，不调用 completeBlock
               }
               // 如果下载成功，并且成功捕获代理方法，则需要对图片进行转换
               // 多用于 图片组 策略，需要不断获取图片
               else if (downloadedImage && (!downloadedImage.images || (options & SDWebImageTransformAnimatedImage)) && [self.delegate respondsToSelector:@selector(imageManager:transformDownloadedImage:withURL:)]) {
                   // 全局队列中，异步操作
                   // 询问代理是否要在 image 存储到缓存之前做最后的图片编号操作（缩放、剪切、圆角等）
                   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                       // 根据代理方法获取转换后的图片
                       UIImage *transformedImage = [self.delegate imageManager:self transformDownloadedImage:downloadedImage withURL:url];
                       // 如果图片存在 并且 转换已经完成
                       if (transformedImage && finished) {
                           // 将图片存入缓存
                           BOOL imageWasTransformed = ![transformedImage isEqual:downloadedImage];
                           [self.imageCache storeImage:transformedImage recalculateFromImage:imageWasTransformed imageData:(imageWasTransformed ? nil : data) forKey:key toDisk:cacheOnDisk];
                       }
                       // 同步调用 completedBlock
                       dispatch_main_sync_safe(^{
                           if (strongOperation && !strongOperation.isCancelled) {
                               completedBlock(transformedImage, nil, SDImageCacheTypeNone, finished, url);
                           }
                       });
                   });
               }
               else {
                   // 没有实现代理方法，进行缓存操作
                   if (downloadedImage && finished) {
                       [self.imageCache storeImage:downloadedImage recalculateFromImage:NO imageData:data forKey:key toDisk:cacheOnDisk];
                   }
                   // completedBlock 回调
                   dispatch_main_sync_safe(^{
                       if (strongOperation && !strongOperation.isCancelled) {
                           completedBlock(downloadedImage, nil, SDImageCacheTypeNone, finished, url);
                       }
                   });
               }
           }
           // 确认结束，从 operation list 删除
           if (finished) {
               @synchronized (self.runningOperations) {
                   if (strongOperation) {
                       [self.runningOperations removeObject:strongOperation];
                   }
               }
           }
       }];
       operation.cancelBlock = ^{
           // 调用 cancel 方法，这个是 download 的 operation，具体实现先后文
           [subOperation cancel];
           
           // 对 runningOperations 加互斥锁
           @synchronized (self.runningOperations) {
               // 转为 __strong 保证生命周期
               __strong __typeof(weakOperation) strongOperation = weakOperation;
               if (strongOperation) {
                   // 从 opertaion list 中删除
                   [self.runningOperations removeObject:strongOperation];
               }
           }
       };
   }
   else if (image) {
       // 缓存查询命中图片
       // 线程没用被取消
       dispatch_main_sync_safe(^{
           __strong __typeof(weakOperation) strongOperation = weakOperation;
           if (strongOperation && !strongOperation.isCancelled) {
               completedBlock(image, nil, cacheType, YES, url);
           }
       });
       @synchronized (self.runningOperations) {
           [self.runningOperations removeObject:operation];
       }
   }
   else {
       // 图像不在缓存中且下载失效
       // 直接调用 completedBlock
       dispatch_main_sync_safe(^{
           __strong __typeof(weakOperation) strongOperation = weakOperation;
           if (strongOperation && !weakOperation.isCancelled) {
               completedBlock(nil, nil, SDImageCacheTypeNone, YES, url);
           }
       });
       @synchronized (self.runningOperations) {
           [self.runningOperations removeObject:operation];
       }
   }
}];

return operation;
```

在分析完冗长的代码之后，来整体把握一下 `SDWebImageManager` 做了哪些事情：

#### 1. 持有 Cache 和 Downloader 协同处理

在上述代码中，经常可以看到 Cache 和 Downloader 的身影。

```c
queryDiskCacheForKey:
```

Cache 是图片获取的最快方式，所以在任何的 sd_set 方法上，无需立即开启 downloader 进行下载操作，而是先根据 key 从 cache 中查询。这里的 key 就是图片对应的 url 。

对于 Cache 的原理，在后续文中会做详细描述。

```c
downloadImageWithURL:
```

在 Cache 查询中无法命中后，需要启动 Downloader 进行图片下载。这个方法也是 Downloader 对外暴露的接口方法，我们可以主动调用该方法进行图片下载工作。

对于 Downloader 的原理，在后续文中会做详细描述。

#### 2. 缓存策略与下载策略的映射

在上文中列举出了所有的缓存策略，其实在 Downloader 中有定义下载策略的枚举。具体代码后续文中会写出，这里列出一个映射图：

![options](http://7xwh85.com1.z0.glb.clouddn.com/options.png)

下载策略是根据缓存策略而决定的，而当需要重新刷新缓存策略生效的时候，会启动策略调整操作。这样保证了各个策略的协调不冲突。

#### 3. 运用 NSMutableSet 进行 url 合法性管理

```c
isFailedUrl = [self.failedURLs containsObject:url];
```

源码中有这么一行代码，用来判断 url 是否合法。

在容器类使用上，SD 使用了 NSMutableSet ，即实现了去重，又增加了查询速度。对于 NSSet 的实现，笔者还没有具体的了解，而在 Google 上的大多数资料说 NSSet 是通过 hash 来实现的。这也难怪查询元素的时候的低时间开销。

而对于每个图片的 url，SD 为了优化，将 image 对应的 url 通过关联对象添加至各个 UIImageView（UIButton），实现了更加高效的访问。所以说，在 url 的管理上，SD 的做法非常值得借鉴。

#### 4. 时刻注意因异步带来的选择竞争问题

在整个流程中，会经常看到增加互斥量的操作。因为 SD 在不断的开启子线程进行下载操作，所以在管理 operation 或者 url 的时候，一定要考虑到这些问题。

## Manager 的流程一览

来总结一下 `SDWebImageManager` 在图片获取的过程中所经历的所有流程：


![manage](http://7xwh85.com1.z0.glb.clouddn.com/manager.png)

其中，很多合法性判断过程中，如果不满足继续下载的合法条件，则会直接调用 completedBlock 回调，并返回未下载成功的 operation 操作对象。

## 写在最后

至此，我们完成了对 `SDWebImageManager` 的分析。该系列下一篇文将对 downloader class 进行详细剖析。


> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。


