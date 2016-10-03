> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/SDWebImage3/)

# SDWebImage Source Probe: Downloader

为了进行图片下载操作，通过 `SDWebImageManager` 这座桥梁，有效控制了图片下载的时机和同缓存的协同操作。这篇来关注一下在 SD 中，Downloader Class 的具体实现。

## Downloader 中的一些枚举

在 `SDWebImageDownloader.m` 中，可以发现这么一个属性：

```objc
@property (strong, nonatomic) NSOperationQueue *downloadQueue;
```

`NSOperation` 表示一个独立的控制单元，也就是我们所说的线程。而 `NSOperationQueue` 控制着这些并行操作的执行，以队列的数据结构特点，从而实现线程优先级的控制。而在 `SDWebImage` 中，很显然是用来管理 `SDWebImageDownloaderOperation` 。对于 `SDWebImageDownloaderOperation` 后面将会单独放在一篇博文中介绍。

同 Manager 一样，我们先来看看在 `.h` 文件中所有的下载模式枚举。

```objc
typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    // 低优先级（常用）
    SDWebImageDownloaderLowPriority = 1 << 0,
    // 显示下载进程
    SDWebImageDownloaderProgressiveDownload = 1 << 1,

    // 默认情况下是不需要 NSURLCache 的。
    // 如果启用这个模式，缓存策略将会更改成 NSURLCache
    SDWebImageDownloaderUseNSURLCache = 1 << 2,

    // 如果图片是从 NSURLCache 中读取到的，则使用 nil 来作为回调 block 的传入参数
    // 常常会与 SDWebImageDownloaderUseNSURLCache 组合使用
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    
    // 当设备为 iOS 4 以上的情况，则在后台可以继续下载图片
    // 通过向系统额外申请时间来完成数据请求操作
    // 如果后台任务终止，则操作会取消
    SDWebImageDownloaderContinueInBackground = 1 << 4,

    // 设置 NSMutableURLRequest.HTTPShouldHandleCookies = YES
    // 从而处理存储在 NSHTTPCookieStore 的 cookie
    SDWebImageDownloaderHandleCookies = 1 << 5,

    // 允许使用不受信的 SSL 证书
    // 主要用于测试
    // 常用在开发环境下
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,

    // 图片放在优先级更高的队列中
    SDWebImageDownloaderHighPriority = 1 << 7,
};
```

另外，对于下载顺序，SD 也为我们提供了两种不同的下载顺序枚举：

```objc
typedef NS_ENUM(NSInteger, SDWebImageDownloaderExecutionOrder) {
    // 先进先出 默认操作顺序
    SDWebImageDownloaderFIFOExecutionOrder,

    // 后进先出
    SDWebImageDownloaderLIFOExecutionOrder
};
```

options 枚举已经几乎将所有的开发场景所需要的模式考虑进来。下面我们来看一看具体的实现代码。

## Downloader 的私有成员对象 

先来看下 Class 的 property 对象的作用：

```objc
@interface SDWebImageDownloader ()

// NSOperation 操作队列
@property (strong, nonatomic) NSOperationQueue *downloadQueue;

// 最后添加的 Operation ，顺序为后进先出顺序
@property (weak, nonatomic) NSOperation *lastAddedOperation;

// 图片下载类
@property (assign, nonatomic) Class operationClass;

// URL 回调字典
// key 是图片的 URL
// value 是一个数组，包含每个图片的回调信息
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;

// HTTP 头信息
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;

// 并行的处理所有下载操作的网络响应
// 实现网络序列化的实例
// 对于 URLCallbacks 的所有修改，都需要放在 barrierQueue 中，并通过 dispatch_barrier_sync 形式
// 用于保证线程安全性
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;

@end
```

由于需要保证多个图片可以同时下载，为了保证 `URLCallbacks` 的线程安全，我们使用 GCD 中的 `dispatch_barrier_sync` 为进程设置**栅栏(barrier)**，它会等待所有位于栅栏函数之前的操作执行完成后再执行，并且在栅栏函数执行完成后，其后续操作才会开始执行，这个函数需要同 `dispatch_queue_create` 生成的 Dispatch 的**同步队列**(Concurrent Dispatch Queue)共同使用。

有了这些对于类成员的认识，开始阅读 Downloader 的源码：

```objc
/**
 *  下载操作
 *
 *  @param url            下载 URL
 *  @param options        下载操作选项
 *  @param progressBlock  过程 block
 *  @param completedBlock 完成 block
 *
 *  @return 遵循 SDWebImageOperation 协议的对象
 */
 - (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    
    // 定义下载 operation
    __block SDWebImageDownloaderOperation *operation;
    // weakly self 接触引用环
    __weak __typeof(self)wself = self;

    // 添加回调闭包，传入URL、过程 block、完成 block
    [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^{
        // 设置下载时限，默认为 15 秒
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }
        // 创建 HTTP 请求，并根据下载模式枚举设置相关属性
        // 为了防止有可能出现的重复缓存问题，如果没有显式声明需要缓存管理，则不启用图片请求的缓存操作
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
       	// 是否处理 cookie
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        // 是否需要传输数据
        // 返回在接到上一个请求的响应之前，是否需要传输数据
        request.HTTPShouldUsePipelining = YES;
        // 设置请求头，需要根据需要过滤指定 URL
        if (wself.headersFilter) {
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        }
        // 创建下载 operation
        operation = [[wself.operationClass alloc] initWithRequest:request
                                                        inSession:self.session
                                                          options:options
                                                         progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                                                             // strongly self，保证生命周期
                                                             SDWebImageDownloader *sself = wself;
                                                             if (!sself) return;
                                                             // URL 回调数组，以 URL 为 key 存储回调 callback
                                                             __block NSArray *callbacksForURL;
                                                             dispatch_sync(sself.barrierQueue, ^{
                                                                 // 从全局字典中获取指定的 callback
                                                                 callbacksForURL = [sself.URLCallbacks[url] copy];
                                                             });
                                                             for (NSDictionary *callbacks in callbacksForURL) {
                                                                 // 执行运行时指定图片的回调 block
                                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                                     SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                                                                     if (callback) callback(receivedSize, expectedSize);
                                                                 });
                                                             }
                                                         }
                                                        completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                                                            // strongly self, 保证生命周期
                                                            SDWebImageDownloader *sself = wself;
                                                            if (!sself) return;
                                                            // 完成时 callback 取方法与上方相同
                                                            // 因为是使用字典进行管理
                                                            __block NSArray *callbacksForURL;
                                                            
                                                            // 需要注意的是，这里使用了栅栏函数解决了选择竞争问题
                                                            dispatch_barrier_sync(sself.barrierQueue, ^{
                                                                callbacksForURL = [sself.URLCallbacks[url] copy];
                                                                if (finished) {
                                                                    [sself.URLCallbacks removeObjectForKey:url];
                                                                }
                                                            });
                                                            for (NSDictionary *callbacks in callbacksForURL) {
                                                                SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                                                                if (callback) callback(image, data, error, finished);
                                                            }
                                                        }
                                                        cancelled:^{
                                                            // strongly self，保证生命周期
                                                            SDWebImageDownloader *sself = wself;
                                                            if (!sself) return;
                                                            // 与前方的执行操作进行栅栏隔离操作
                                                            // 保证在删除的时候没有执行自定对于 callback 的读写操作
                                                            dispatch_barrier_async(sself.barrierQueue, ^{
                                                                [sself.URLCallbacks removeObjectForKey:url];
                                                            });
                                                        }];
        // 是否需要对图片进行压缩处理
        operation.shouldDecompressImages = wself.shouldDecompressImages;
        
        // 认证请求操作，后面详细分析
        if (wself.urlCredential) {
            operation.credential = wself.urlCredential;
        } else if (wself.username && wself.password) {
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        // 设置下载操作的优先级操作，需要根据下载模式枚举来判断
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }
        
        // 向下载操作的队列中增加当前操作
        [wself.downloadQueue addOperation:operation];
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // 如果执行顺序为后进先出的栈结构
            // 则将新添加的 operation 作为当前最后一个 operation 的依赖，按照顺序逐个执行
            [wself.lastAddedOperation addDependency:operation];
            wself.lastAddedOperation = operation;
        }
    }];
```

整个流程已经了解，下面分析一些细小的细节问题：

## 全局字典，将 URL 与回调 block 的映射容器

```objc
__block NSArray *callbacksForURL;

dispatch_sync(sself.barrierQueue, ^{
// dispatch_barrier_sync (sself.barrierQueue, ^{
	callbacksForURL = [sself.URLCallbacks[url] copy];
});
for (NSDictionary *callbacks in callbacksForURL) {
	dispatch_async(dispatch_get_main_queue(), ^{
		SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
		if (callback) callback(receivedSize, expectedSize);
	});
}
```

在执行进行中 block、完成 block 的时候，都会使用以上这几行代码。其作用是为了维护一个字典，key 为图片的唯一标识 url ，值为一个 block 的数组，来统一管理这些回调方法。其大致的结构图如下表示：

![URLCallBacks](http://7xwh85.com1.z0.glb.clouddn.com/URLCallBacks.png)
(图片来源：[polobymulberry](http://www.cnblogs.com/polobymulberry/p/5017995.html#_label4))

执行过程中的 block 的时候，在初始化字典管理的时候使用了 `dispatch_sync` 同步执行操作，而没有增加栅栏函数（注释中为增加栅栏函数）。但在对于完成 block 的管理时，为了保证线程安全的竞争选择问题，SD 作者选用了栅栏函数对线程进行了先后执行的规定。为什么这里不用栅栏呢？笔者的理解如下：**由于这两个位置，都是对于 `URLCallbacks` 的读写操作，而在这之前是没有任何更新 `URLCallbacks` 的操作，所以不需要设置栅栏，只需要同步继续即可。而对于栅栏函数，是用在异步操作中对于操作顺序进行控制，由于 SD 需要支持多图片同时下载，所以需要在每次的 `URLCallbacks` 写数据结束后，再进行读操作。**

## NSMutableURLRequest 网络请求

```objc
NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url
                                                                    cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData)
                                                                timeoutInterval:timeoutInterval];
```

`initWithURL` 的作用是根据 url 、缓存策略（Cache Policy）、下载最大时限（Time Out Interval）来产生一个 `NSURLRequest`。先来看下缓存策略的选择：

* **SDWebImageDownloaderUseNSURLCache**：在 SDWebImage 中，默认条件下，请求是不使用 `NSURLCache` 的。如果使用该选项，`NSURLCache` 就应该使用默认的缓存策略 `NSURLRequestUseProtocolCachePolicy`。
* **NSURLRequestUseProtocolCachePolicy**：对特定 url 请求使用网络协议（例如 HTTP）中实现的缓存逻辑。这是一个默认的策略。该策略表示如果缓存不存在，直接从服务端获取。如果缓存存在，会根据 Response 中的 Cache-Control 字段判断下一步操作。例如：当 Cache-Control 字段为 must-revalidata ，则会询问服务端该数据是否有更新，无更新则返回给用户缓存数据，若已经更新，则请求服务器以获取最新数据。
* **NSURLRequestReloadIgnoringLocalCacheData**：数据需要从原始地址（一般就是重新从服务器获取）。不使用现有缓存。

```objc
// 要点一
request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);

// 要点二
request.HTTPShouldUsePipelining = YES;

// 要点三
if (wself.headersFilter) {
	request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
}
else {
	request.allHTTPHeaderFields = wself.HTTPHeaders;
}
```

后面就是对于 request 的一些属性的设置，从属性名上可以看出使用的是 HTTP 协议：

* 要点一：`HTTPShouldHandleCookies` 如果设置为 YES，在处理时我们直接查询 `NSHTTPCookieStore` 中的 cookies 即可。`HTTPShouldHandleCookies` 这个策略表示是否应该给 Request 设置 cookie 并伴随着 Request 一起发送出去。然后 Response 返回的 cookie 会继续根据访问策略（Cookie Acceptance Policy）接收到系统中。
* 要点二：`HTTPShouldUsePipelining` 表示 receiver （常常理解为 client 客户端）的下一个信息是否必须等到上一个请求回复才能发送。如果为 YES 表示可以， NO 反之。这个就是我们常常提到的 **HTTP 管线化**（HTTP Pipelining），如此可以显著降低请求的加载时间。
* 要点三：`headersFilter` 是使用自定义方法来设置 HTTP 的 Head Filed。这里可以看下 HTTPHeader 的初始化（下载 webp 图片与通常情况下的 header 不同）：

```objc
#ifdef SD_WEBP
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
#else
        _HTTPHeaders = [@{@"Accept": @"image/*;q=0.8"} mutableCopy];
#endif
```

## NSURLCredential 身份认证


> web 服务可以在返回 HTTP 响应时附带认证要求的 Challenge，作用是询问 HTTP 请求的发起方是谁，这时候发起方应提供正确的用户名和密码（认证信息），然后 web 服务才会返回真正的 HTTP 响应。

> 收到认证要求时，`NSURLConnection` 的委托对象会收到相应的消息并得到一个 `NSURLAuthenticationChallenge` 实例。该实例的发送方遵守 `NSURLAuthenticationChallengeSender` 协议。为了继续收到真实的数据，需要向该发送方向发回一个 `NSURLCredential` 实例。

```objc
if (wself.urlCredential) {
  operation.credential = wself.urlCredential;
} else if (wself.username && wself.password) {
  operation.credential = [NSURLCredential credentialWithUser:wself.username
                                                    password:wself.password
                                                 persistence:NSURLCredentialPersistenceForSession];
}
```

当已经有用 `NSURLCredential` ，则直接使用，没有的话则重新构建一个实例并存储下来。`NSURLCredential` 在其中的作用就是缓存对于证书的授权处理。这是对于 https 协议而言，如果想了解更多建议阅读 [Foundation的官方文档](https://developer.apple.com/reference/foundation/nsurlcredential)。

## 总结

在 Downloader 中，主要的操作就是用于组织一个 `URLCallbacks` 字典，用于管理图片指定的进行 block 、完成 block。并且，在 `downloadImageWithURL:` 方法中，Downloader 其实一直在更新一个 operation 并作为返回值。所以，Downloader 的主要作用是实现多图片异步下载请求，并将其封装为一个 operation 提交给上层统一管理。

下一篇主要讲解一下 DownloaderOperation 下载操作任务管理。





> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。


