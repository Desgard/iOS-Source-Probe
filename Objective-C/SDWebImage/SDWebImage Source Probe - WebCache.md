> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/SDWebImage1/)

# SDWebImage Source Probe: WebCache

最近两天，在完成工作业务之余，除了看书，自己也要开始深入的阅读经典的源码。来完善我的 [iOS 源码探求](https://desgard.com/iOS-Source-Probe/) 系列文章。

对源码的阅读是一个长久的学习过程，我会将业务中最常用的一些经典三方库拿出来进行学习。这一点我很敬佩 [@Draveness](http://draveness.me/) 的精神，并向他看齐。

## SDWebImage 简单介绍

[SDWebImage](https://github.com/rs/SDWebImage) 根据官方文档，其实就是提供了以下功能：

> Asynchronous image downloader with cache support with an UIImageView category.

一个异步下载图片并且带有 `UIImageView` Category 的缓存库。其好用的原因还在于其简介的接口。话不多说，开始主要内容。本系列文章使用的 SDWebImage 版本为 `v3.8.1`。

## 多重入口委托构造器

在使用 SD 库的时候，最常调用的方法如下： 

```c
[self.imageView sd_setImageWithURL:[NSURL URLWithString:@"url"] 
				placeholderImage:[UIImage imageNamed:@"placeholder.png"]];
```

由此，对 `UIImageView` 的图片一部加载完成了。进入到该方法内部，在其 `.h` 的文件中看到以下接口：

```c
- (void)sd_setImageWithURL:(NSURL *)url;
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder;
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options;
...
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock;
```

作为 SD 的入口函数，在 sd_setImageWithURL 方法中采用了多种参数灵活搭配的同名方法。而内部实质，都在向最后一个 sd_setImageWithURL 传入参数最多的方法进行调用处理。

在 c++ 0x 中，这种方式被广泛的使用在系统库的 class 中作为类的委托构造器（Delegate Constructor）。这样做的好处是，**可以清晰的梳理函数构造逻辑，减轻代码编写量**。

## setImageWithURL 处理流程

```c
// 委托构造器最高级入口
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock {
	// 【要点 1】取消该 UIImageView 的下载队列
    [self sd_cancelCurrentImageLoad];
    
    // 【要点 2】对应的 UIImageView 增加一个对应的 url 属性
    objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	// 根据参数条件，是一个 optional 执行块
	// 在未发送请求过去网络图片之前，增加 placeHolder
	// 如果有 delay 延迟标记
    if (!(options & SDWebImageDelayPlaceholder)) {
    	// 创建主线程异步队列来更新 UI
        dispatch_main_async_safe(^{
            self.image = placeholder;
        });
    }
    
    // 判断 url 是否为空
    if (url) {
        // 是否展示 ActivityIndicator 
        if ([self showActivityIndicatorView]) {
            [self addActivityIndicator];
        }
		// 防止 block 的 retain cycle，进行弱引用转换
        __weak __typeof(self)wself = self;
        // 使用图片 download 方法，并完成 callback 回调
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadImageWithURL:url options:options progress:progressBlock completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
	        // 停止 ActivityIndicator 转动
            [wself removeActivityIndicator];
            if (!wself) return;
            dispatch_main_sync_safe(^{
                if (!wself) return;
                // 图片是否使用了默认参数
                if (image && (options & SDWebImageAvoidAutoSetImage) && completedBlock)
                {
                	// 【要点 3】对 download 中的 completedBlock 成员传参
                    completedBlock(image, error, cacheType, url);
                    return;
                }
                else if (image) {
                	// 更新图片，需要重新进行 layout 布局，主动调用 setNeedsLayout 方法
                    wself.image = image;
                    [wself setNeedsLayout];
                } else {
                    if ((options & SDWebImageDelayPlaceholder)) {
                        wself.image = placeholder;
                        [wself setNeedsLayout];
                    }
                } 
                // 判断 finished 标记，传入 block 方法参数
                if (completedBlock && finished) {
                    completedBlock(image, error, cacheType, url);
                }
            });
        }];
        // 将上面的 operation 添加到字典中，key 为 UIImageViewImageLoad
        [self sd_setImageLoadOperation:operation forKey:@"UIImageViewImageLoad"];
    } else {
    	// 处理 url 为 nil 的状态
    	// 保证在主线程中处理，因为涉及到 UI
        dispatch_main_async_safe(^{
            [self removeActivityIndicator];
            if (completedBlock) {
                NSError *error = [NSError errorWithDomain:SDWebImageErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
                completedBlock(nil, error, SDImageCacheTypeNone, url);
            }
        });
    }
}
```

下面来看深入看一下上述代码注释中的 3 个要点。

* [self sd_cancelCurrentImageLoad]

进入函数内层是以下代码：

```c
- (void)sd_cancelCurrentImageLoad {
	// 通过 key 来取消操作
    [self sd_cancelImageLoadOperationWithKey:@"UIImageViewImageLoad"];
}
```

```c
// UIView+WebCacheOperation.m

- (void)sd_cancelImageLoadOperationWithKey:(NSString *)key {
    // Cancel in progress downloader from queue
    // 取消正在下载的队列
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    id operations = [operationDictionary objectForKey:key];
    // 如果 operationDictionary 可以取到 key，则可以得到与该视图相关的操作
    // 并根据 key 从字典中取消这些操作
    if (operations) {
    	// 检查 operations 是否为 array ，防止重名
        if ([operations isKindOfClass:[NSArray class]]) {
        	// 比那里当中所有遵循给定代理的对象，对其下载任务进行取消
            for (id <SDWebImageOperation> operation in operations) {
                if (operation) {
                    [operation cancel];
                }
            }
        // 如果不是集合，那么可能是一个下载对象
        } else if ([operations conformsToProtocol:@protocol(SDWebImageOperation)]){
            [(id<SDWebImageOperation>) operations cancel];
        }
        // 所有元素已过滤，删除 key
        [operationDictionary removeObjectForKey:key];
    }
} 
```

从代码中，可以看出：SD 使用 `NSDictionary` 来管理满足 `SDWebImageOperation` 代理的实例。通过对代理实例的判断，以及使用键值查询 operation 的方式，SD 可以有效、迅速的管理所有下载任务。

* objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

这里是使用关联对象（Associated Object）（如果这里陌生，可以查阅 *[浅谈Associated Objects](https://desgard.com/Associated-Objects/)* 这篇博文），来对 UIImageView 做了一个关联值。在第二个参数上，一般是关联对象的唯一标记，在 *UIImageView_WebCache.m* 中使用了一个静态量地址来作为这个 key。

```c
static char imageURLKey;
```

增加这个 url 属性便于在其他地方迅速访问。在获取时候，只需要调用 `- (NSURL *)sd_imageURL` 便可以直接通过关联对象迅速查询。这个 url 的访问在其他地方会有多次调用。

* completedBlock(image, error, cacheType, url);

默认情况下，SD 会等 image 完全从网络下载完成之后，直接替换 UIImageView 中的 image 。如果想在获取图片之后，手动处理之后的所有事情，则需要设置此方法。

这个方法是将会在 `SDWebImageManager.h` 出现。

## setAnimationImagesWithURLs 图片组

在这个 Category 中，还有对于动画组图的设置。观看源码可知，这个方法在实现上是将多个图片的 URL 打包成 array，传入 `sd_setImageLoadOperation` 方法来增加图片加载的 Operation 。而在打包中，相当于多次执行了 `sd_setImageWithURL` （其中的处理细节是一样的）。唯一不同的是，`setAnimationImagesWithURLs` 没有去设置关联对象。因为在展示中，我不需要对其做任何的控制，所以也就没有提供访问的快捷方法。

## UIImageView+WebCache.m 源码解读总结

对于常用的 `setImageWithURL` 方法，可以总结成以下流程：

![UIImageView+WebCache](http://7xwh85.com1.z0.glb.clouddn.com/UIImageView+WebCache.png)

从最常用的 `setImageWithURL` 可以看出，其实 SDWebImage 的逻辑很清晰，其源码阅读起来可读性也很高。

在阅读三方库源码的同时，也可以感受到作者的代码经验所在。如同委托构造的方式，也是经验的积累总结。所以在学习代码的同时，也可以学习编码思想。

## 延伸阅读

[cocoadocs SDWebImage](http://cocoadocs.org/docsets/SDWebImage/3.7.0/Categories/UIImageView+WebCache.html#//api/name/sd_setAnimationImagesWithURLs:)

[iOS 源代码分析----SDWebImage](http://draveness.me/ios-yuan-dai-ma-jie-xi-sdwebimage/)

> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。


