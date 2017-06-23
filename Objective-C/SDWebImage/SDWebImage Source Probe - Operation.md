> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/SDWebImage4/)


# SDWebImage Source Probe: Operation

很久没有更博客，最近都在忙着毕业设计和一些小项目，所以学习精力有些分散，读源码的时间大幅度缩水。是时候继续更新了。

在解读 Operation 部分的源码之前，需要先了解一下关于 `NSURLSession` 的一些知识。

## 对于 NSURLSession 的一些知识

`NSURLSession` 是于 2013 年随着 iOS 7 一同面世的，苹果公司对于其的定位是作为 `NSURLConnection` 的替代者，然后逐步推广。现在最广泛使用的第三方网络框架 `AFNetworking` 以及这套博文分析的 `SDWebImage` 等等都在使用 `NSURLSession`。

在 OSI 计算机网络体系结构中，自外向里的第三层*会话层*，我们可以将 NSURLSession 理解为会话层。这一层通常用于管理网络接口的创建、维护、删除等等工作。

`NSURLSession` 和 `NSURLConnection` 都提供了与各种协议，例如 HTTP 和 HTTPS，进行交互的 API。在官方文档中对其的描述，这是一种高度可配置的 `Container`，通过其提供的 API 可以进行很细微的管理控制。`NSURLSession` 提供了 `NSURLConnection` 中的所有特性，在功能上可以称之为后者的超集。

使用 `NSURLSession` 最基本单元就是 `Task`，这个是 `NSURLSessionTask` 的实例。有三种类型的任务：`NSURLSessionDataTask`、`NSURLSessionDownloadTask` 和 `NSURLSessionUploadTask`。

我们使用 `NSURLSessionDownloadTask` 来创建一个下载 `Task`。

```c
// 设置配置类型，这里我们使用默认配置类型，改类型下，会将缓存文件存储在磁盘上
NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];  
// 通过 sessionConfiguration 创建 session 对象实例，并设置代理对象
NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
// 通过创建的 session 对象创建下载 task，传入需要下载的 url 属性
NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:@"http://www.desgard.com/assets/images/logo-new.png"]];  
// 执行给定下载 task
[downloadTask resume];  
```

通过此例我们了解了 NSURLSession 用于网络会话层工作。是网络接口的管理层对象，在网络数据传输中，起到桥梁的作用。

## Operation 的 start 开启方法

在 Downloader 一文中，我们知道 SDWebImage 下载图片是通过构造一个 Operation(NSOperation) 来实现的，并且会追加放入 downloadQueue ( `NSOperationQueue` )中。所以下载任务用实例化描述，即一个 Operation。

NSOperation 一般是用来操作或者执行一个单一的任务，如果任务不复杂，其实是可以使用 Cocoa 中的 NSOperation 的派生类 `NSBlockOperation` 和 `NSInvocationOperation`。当其无法满足需求时，我们可以像 SDWebImage 一样去定制封装 NSOperation 的子类。关于 NSOperation，又可以归为两类：**并发(concurrent)** 和 **非并发(non-concurrent)**，而在 SDWebImage 中可视作并发类型。

来看 SDWebImage 中对于 `start` 函数的重写：

```c
// 重写 NSOperation 的 start 方法
// 更加灵活的管理下载状态，创建下载所使用的 NSURLSession 对象
- (void)start {
    // 互斥锁，保证此时没有其他线程对 self 对象进行修改
    // 线程保护作用
    @synchronized (self) {
        // 管理下载状态
        // 如果取消状态下载，则更改完成状态
        if (self.isCancelled) {
            self.finished = YES;
            [self reset];
            return;
        }

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
        // 后台运行的权限
        if (hasApplication && [self shouldContinueWhenAppEntersBackground]) {
            __weak __typeof__ (self) wself = self;
            UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
            // 标记一个可以在后台长时间运行的后台任务
            self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
                __strong __typeof (wself) sself = wself;
                // 当应用程序留给后台的时间快要结束时
                // 执行当前回调
                // 进行清理工作（主线程），如果失败则抛出 crash
                if (sself) {
                    [sself cancel];
                    // 标记指定的后台任务完成
                    [app endBackgroundTask:sself.backgroundTaskId];
                    // 销毁后台任务标识符
                    sself.backgroundTaskId = UIBackgroundTaskInvalid;
                }
            }];
        }
#endif
        NSURLSession *session = self.unownedSession;
        if (!self.unownedSession) {
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            sessionConfig.timeoutIntervalForRequest = 15;
            
            /**
             *  为这个 task 创建 session
             *  将 nil 作为 delegate 队列进行传递，以便创建一个 session 对象用于执行 delegate 的串行操作队列
             *  以完成方法以及 handler 回调方法的调用
             */
            self.ownedSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                              delegate:self
                                                         delegateQueue:nil];
            session = self.ownedSession;
        }
        
        // 创建数据任务
        self.dataTask = [session dataTaskWithRequest:self.request];
        // 正在执行属性标记
        self.executing = YES;
        self.thread = [NSThread currentThread];
    }
    
    // 启动任务
    [self.dataTask resume];

    if (self.dataTask) {
        if (self.progressBlock) {
            // 设置默认图片的大小，用未知枚举类型标记
            self.progressBlock(0, NSURLResponseUnknownLength);
        }
        // 在主线程中发送下载开始通知
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:self];
        });
    }
    else {
        // 创建失败，直接执行回调部分
        if (self.completedBlock) {
            self.completedBlock(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Connection can't be initialized"}], YES);
        }
    }

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_4_0
    // 停止在后台的执行操作
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if(!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
        UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
        [app endBackgroundTask:self.backgroundTaskId];
        self.backgroundTaskId = UIBackgroundTaskInvalid;
    }
#endif
}
```

对于一个并发类 NSOperation ，在重写 `start` 方法时，需要去实现异步(asynchronous) 方式来处理事件。在 SDWebImage 中，可以看到类的成员对象中的 `self.thread` 来承载 operation 任务的执行动作。并且还处理了后台运行时的状态。

我们来具体剖析一下这段代码：

在 `NSOperation` 中共有三个状态，这些状态可以及时的判断 `SDWebImageDownloaderOperation` 是否被取消了。如果取消，则认为该任务已经完成，并且需要及时回收资源，即 `reset` 方法。使用 `NSOperation` 需要手动管理以下三个状态：

* `isExecuting` - 代表任务正在执行中
* `isFinished` - 代表任务已经完成
* `isCancelled` - 代表任务已经取消执行

```Objc
if (self.isCancelled) {
	self.finished = YES;
	[self reset];
	return;
}
```

接下来一段宏中的代码，以考虑到 App 进入后台中的发生的事。在 SD 中使用了 `beginBackgroundTaskWithExpirationHandler:` 来申请 App 进入后台后额外的占用时间，所以我们要拿出 `UIApplication` 这个类，并使用 `[UIApplication sharedApplication]` 这个单例来调用对应方法。考虑到 iOS 的通用性和版本问题，SD 在调用该单例时进行了**双重检测**：

```Objc
Class UIApplicationClass = NSClassFromString(@"UIApplication");
BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
```

再之后是系统后台任务的代码，这里来聊一聊 `beginBackgroundTaskWithExpirationHandler` 这个回调。`beginBackgroundTaskWithExpirationHandler` 不是意味着立即执行后台任务，它相当于**注册了一个后台任务**，而之后的 `handler` 表示 **App 在直到后台运行的时机到来后在运行其中的 block 代码逻辑**。所以我们仍旧需要判断下载任务的下载状态，如果下载任务还在进行，就需要取消该任务（`cancel`方法）。这个方法也是在 `SDWebImageDownloaderOperation` 中定义的，下午将会介绍。

在做完进入后台情况的处理，也就是图片的“善后处理”之后，进入图片下载的正题部分。下载一个单文件对应的是一次网络请求。所以需要用 `NSURLSession` 来创建一个 task 处理这个请求。

```objc
NSURLSession *session = self.unownedSession;
if (!self.unownedSession) {
	NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
	sessionConfig.timeoutIntervalForRequest = 15;
  
	/**
	*  为找个 task 创建 session
	*  将 nil 作为 delegate 队列进行传递，以便创建一个 session 对象用于执行 delegate 的串行操作队列
	*  以完成方法以及 handler 回调方法的调用
	*/
	self.ownedSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                    delegate:self
                                               delegateQueue:nil];
	session = self.ownedSession;
}
   
// 创建数据任务
self.dataTask = [session dataTaskWithRequest:self.request];
// 正在执行属性标记
self.executing = YES;
self.thread = [NSThread currentThread];
```

首先取出 session 成员，因为我们需要下载多个图片，不需要为每次请求都进行握手操作，所有复用 `NSURLSession` 对象。如果发现其未初始化，则对其重新配置。在构造方法中，选用 `defaultSessionConfiguration`，这个是默认的 session 配置，类似于 `NSURLConnection` 的标准配置，使用硬盘来存储缓存数据。之后创建请求，增加标记，获取当前线程。

## 任务取消 cancel 方法

```objc
- (void)cancel {
    @synchronized (self) {
        // 根据线程是否初始化来查看是否有开启下载任务
        if (self.thread) {
            // 在指定线程中调用 cancelInternalAndStop 方法
            [self performSelector:@selector(cancelInternalAndStop) onThread:self.thread withObject:nil waitUntilDone:NO];
        }
        else {
            // 直接调用 cancelInternal 方法
            [self cancelInternal];
        }
    }
}
```

在 `cancel` 方法中，会有两种处理手段。如果下载任务处于开启状态，则在该实例的持有进程中调用 `cancelInternalAndStop` 方法，否则的话则在当前进程调用 `cancelInternal` 方法。我们来看这两个方法的区别和联系。

```ObjC
- (void)cancelInternalAndStop {
    // 判断 isFinished 标识符
    if (self.isFinished) return;
    [self cancelInternal];
}

- (void)cancelInternal {
    if (self.isFinished) return;
    [super cancel];
    // 执行 cancel 回调
    if (self.cancelBlock) self.cancelBlock();

    if (self.dataTask) {
        // 停止 task 任务
        [self.dataTask cancel];
        dispatch_async(dispatch_get_main_queue(), ^{
            // 发送通知
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
        });

        // 如果我们启用了 cancel 方法，则回调方法不会被执行，并且 isFinished 和 isExecuting 两个标识属性修改状态
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    }
    
    // Operation 初始化操作
    [self reset];
}
```

也许你会有疑问，为什么 `cancelInternalAndStop` 在调用 `cancelInternal` 之前多此一举的判断了 `self.isFinished` 标志符的状态？为什么不写成一个方法？其实这是有历史原因的。请看[这个链接](https://github.com/rs/SDWebImage/commit/5580c78282910716f63210b700c83d3415bdfc08#diff-7519dfc55f22e25bd87d757458d74b82R151)。其中 L155 我们发现了“惊天的秘密”。这里大概讲述一下这个历史原因：在 *SDWebImage* 的 `v3.7.0` 版本及以前，并没有引入 `NSURLSession` 而是采用的 `NSURLConnection`。而后者往往是需要与 Runloop 协同使用，因为每个 Connect 会作为一个 Source 添加到当前线程所在的 Runloop 中，并且 Runloop 会对这个 Connect 对象强引用，以保证代理方法可以调用。

在新版本中，由于启用了 `NSURLSession`，说明 SDWebImage 已经放弃了 iOS 6 及以下的版本。在进行网络请求的处理时更加的安全，这也是历史的必然趋势。当然，笔者也十分开心，因为不用再解读 Runloop 的代码了。😄

## SDWebImageManager 中的 NSURLSessionDataDelegate 代理方法实现

`NSURLSessionDataDelegate` 代理用于实现数据下载的各种回调。在 SD 中由于要处理图片下载的各种状态，所以需要遵循改代理，并去自行管理代理方法返回结果的不同处理。

在 `Response` 数据反馈后，都会传给客户端一个 Http 状态码，根据状态码的不同，需要执行不同情况的处理方法。在 `NSURLSessionDataDelegate` 的代理方法中，即可实现判断状态码的步骤：

```ObjC
// 该方法中实现对服务器的响应进行授权
// 实现后执行 completionHandler 回调
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    
    // 处理返回状态码小于400非304情况
    // 304 属于未返回结果未修改，也属于正常返回
    if (![response respondsToSelector:@selector(statusCode)] || ([((NSHTTPURLResponse *)response) statusCode] < 400 && [((NSHTTPURLResponse *)response) statusCode] != 304)) {
        // 获取文件长度
        // expectedContentLength 获取的是下载文件长度，而不是整个文件长度
        NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
        self.expectedSize = expected;
        if (self.progressBlock) {
            // 执行过程中 block
            self.progressBlock(0, expected);
        }
        
        self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
        self.response = response;
        // 在主线程发送通知消息
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadReceiveResponseNotification object:self];
        });
    }
    else {
        // 获取状态码
        NSUInteger code = [((NSHTTPURLResponse *)response) statusCode];
        
        // 如果状态吗反馈304状态，则代表服务器告知客户端当前接口结果没有发生变化
        // 此时我们cancel掉当前的 Operation 然后从缓存中获取图片
        if (code == 304) {
            [self cancelInternal];
        } else {
            // 其他成功状态直接 cancel 掉 task 即可
            [self.dataTask cancel];
        }
        // 在主线程发送通知消息
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:self];
        });
        // 调用 completedBlock，说明任务完成
        if (self.completedBlock) {
            self.completedBlock(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:[((NSHTTPURLResponse *)response) statusCode] userInfo:nil], YES);
        }
        // 重置 Operation 示例状态，以便复用
        [self done];
    }
    
    // 完成回调
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}
```

通过 `Response` 反馈的 Http 状态码，做出了各种操作。当然这里只要判断出状态码，将各个操作对应上即可。而下面的规划进度回调方案中，则是整个回调方法处理图像的核心部分：

```ObjC
// 接收到部分数据时候的回调
// 用于规划进度
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    // 分块写二进制文件
    [self.imageData appendData:data];
    // 进度控制
    if ((self.options & SDWebImageDownloaderProgressiveDownload) && self.expectedSize > 0 && self.completedBlock) {
        // 以下代码思路来自于 http://www.cocoaintheshell.com/2011/05/progressive-images-download-imageio/
        // 感谢作者 @Nyx0uf

        // 获取图片总大小
        const NSInteger totalSize = self.imageData.length;

        // 更新数据源，需要传递所有数据，而不仅是更新的一部分
        // ImageIO 接口之一，通过 CGImageSourceCreateWithData 对图片二进制文件解码
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)self.imageData, NULL);
        // 长和宽均为0，说明当前下载为第一段数据
        if (width + height == 0) {
            // ImageIO 接口之一，返回包含尺寸以及其他信息，其他信息例如 EXIF、IPTC 等
            CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
            if (properties) {
                NSInteger orientationValue = -1;
                // 从 properties 中拿高度
                CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
                // 获取到后直接记录到 height 变量中
                if (val) CFNumberGetValue(val, kCFNumberLongType, &height);
                val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
                if (val) CFNumberGetValue(val, kCFNumberLongType, &width);
                // 从 properties 中获取图片的其他信息
                val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
                if (val) CFNumberGetValue(val, kCFNumberNSIntegerType, &orientationValue);
                CFRelease(properties);

                // 当我们使用 Core Graphics 绘制操作时，如果失去了 Orientation Information
                // 这说明在 initWithCGImage 初始化阶段错误（与 didCompleteWithError 中 initWithData 不同）
                // 所以需要暂时缓存，延迟传值
                orientation = [[self class] orientationFromPropertyValue:(orientationValue == -1 ? 1 : orientationValue)];
            }

        }
        // 过程中状态
        if (width + height > 0 && totalSize < self.expectedSize) {
            // 创建 CGImage 引用，根据 Source 状态创建图片
            CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
// 通过宏来判断平台
#ifdef TARGET_OS_IPHONE
            // iOS 中图像失真的解决方法
            if (partialImageRef) {
                // 根据引用来获取图像高度属性
                const size_t partialHeight = CGImageGetHeight(partialImageRef);
                // 创建 RGB 色彩空间
                CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
                // 创建图像空间，【参数定义】见下文分析
                CGContextRef bmContext = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
                // 释放色彩空间引用
                CGColorSpaceRelease(colorSpace);
                if (bmContext) {
                    // 图片渲染方法
                    CGContextDrawImage(bmContext, (CGRect){.origin.x = 0.0f, .origin.y = 0.0f, .size.width = width, .size.height = partialHeight}, partialImageRef);
                    CGImageRelease(partialImageRef);
                    // 从上下文中创建 CGImage
                    partialImageRef = CGBitmapContextCreateImage(bmContext);
                    CGContextRelease(bmContext);
                }
                else {
                    // 色彩空间创建失败，直接释放
                    CGImageRelease(partialImageRef);
                    partialImageRef = nil;
                }
            }
#endif

            if (partialImageRef) {
                // 通过 Core Graphics 引用创建图片对象
                UIImage *image = [UIImage imageWithCGImage:partialImageRef scale:1 orientation:orientation];
                // 使用图片的 URL 作为缓存键
                NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:self.request.URL];
                // C++ 的 SDScaledImageForKey 方法入口，用于多倍数缩放图片的处理及缓存
                UIImage *scaledImage = [self scaledImageForKey:key image:image];
                // 解压缩图片
                if (self.shouldDecompressImages) {
                    // 对图片进行解码
                    image = [UIImage decodedImageWithImage:scaledImage];
                }
                else {
                    image = scaledImage;
                }
                CGImageRelease(partialImageRef);
                dispatch_main_sync_safe(^{
                    if (self.completedBlock) {
                        // 完成回调，并传出 image 引用
                        self.completedBlock(image, nil, nil, NO);
                    }
                });
            }
        }

        CFRelease(imageSource);
    }

    if (self.progressBlock) {
        // 过程回调，传出二进制文件已经下载长度和总长度
        self.progressBlock(self.imageData.length, self.expectedSize);
    }
}
```

主要的过程在注释中都有讲述，这里主要说一下注释中标明的一些地方：

#### 创建图像空间的函数原型和参数定义

```ObjC
CGContextRef CGBitmapContextCreate (
   void *data, // 指向要渲染的绘制内存地址，这个内存块的大小至少是（bytesPerRow*height）个字节
   size_t width, // bitmap 的高度，单位为像素
   size_t height, // bitmap 的高度，单位为像素
   size_t bitsPerComponent, // 内存中像素的每个组件的位数，例如 32 位像素格式和 RGB 颜色空间这个值设定为 8
   size_t bytesPerRow, // bitmap 的每一行在内存所占的比特数
   CGColorSpaceRef colorspace, // bitmap上下文使用的颜色空间
   CGBitmapInfo bitmapInfo // 指定bitmap是否包含alpha通道，像素中alpha通道的相对位置，像素组件是整形还是浮点型等信息的字符串。
);
```

当调用这个函数的时候，Quartz 创建一个一个位图绘制环境，也就是位图上下文。当你向上下文中绘制信息时，Quartz 把你要绘制的信息作为位图数据绘制到指定的内存块。

#### imageIO 简介

之前也许你会惊讶于 SD 库对于图片下载进度的处理，其实这些处理都是交给了 Apple 的 Core Graphics 中的 imageIO 部分组件。在处理进度其实是 imageIO 的**渐进加载图片功能**，这里献上[官方文档](https://developer.apple.com/library/content/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_source/ikpg_source.html#//apple_ref/doc/uid/TP40005462-CH218-SW3)。渐进加载图片的过程，只需要创建一个 imageSource 引用即可完成。在上面的源码中也是如此实现的。

> 对于渐进加载，现在已经有很多解决方法。例如 `YYWebImage` 中已经支持了多种渐进式图片加载方案，而不是传统的 `baseline` 方式，[文章链接](http://blog.ibireme.com/2015/11/02/ios_image_tips/)。


## 总结

SD 前面的所有流程，其实都在围绕着这个 Operation 展开的。在 Operation 中处理了关键的网络请求及下载部分，而且其会话的控制全部由 Operation 进行持有和处理。这里关系到多线程和网络的基础知识，如果想进一步了解其实现原理，可以补充一下基础知识。


## 引文

[imageIO---完成渐进加载图片](http://blog.csdn.net/wsxzk123/article/details/44184309)

[认识 Operation](http://greenchiu.github.io/blog/2013/08/06/ren-shi-nsoperation/)

> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。
