> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](http://www.desgard.com/isa/)

# load 方法全程跟踪

几天前 Github 的 [RetVal](https://github.com/RetVal) 大神更新了可 debug 版本的 706 `<objc/runtime.h>` 源码，于是让源码阅读学习得以继续。本文将介绍个人学习 `load` 方法的全部流程。

## load 方法的调用时机

从 *Effective Objective-C 2.0 - 52 Specific Ways to Improve Your iOS and OS X Programs* 一书中讲述到：Objective-C 中绝大多数类都继承自 `NSObject` 根类，每个类都有两个初始化方法，其中之一就是 `load` 方法。

```c
+ (void)load
```

对于每一个 *Class* 和 *Category* 来说，必定会调用此方法，而且仅调用一次。当包含 *Class* 和 *Category* 的程序库载入系统时，就会执行此方法，并且此过程通常是在程序启动的时候执行。

不同的是，现在的 iOS 系统中已经加入了**动态加载特性（Dynamic Loading）**，这是从 macOS 应用程序中迁移而来的特性，等应用程序启动好之后再去加载程序库。如果 *Class* 和其 *Category* 中都重写了 `load` 方法，则先调用 *Class* 中的。

我们通过 [RetVal](https://github.com/RetVal) 封装好的 debug 版最新源码进行断点调试，来追踪一下 `load` 方法的全部处理过程，以便于了解这个函数以及 Objective-C 强大的动态性。

创建一个 *Class* 文件 `DGObject.m`，然后在其中增加 `load` 方法。在运行 proj 后，可以看见 `load` 方法的调用时机是在入口函数主程序之前。

![](http://7xwh85.com1.z0.glb.clouddn.com/14837770930294.jpg)

下面在 `load` 方法下增加断点，查看其调用栈并跟踪函数执行时候的上层代码：

![](http://7xwh85.com1.z0.glb.clouddn.com/14837787124422.jpg)

调用栈显示栈情况为如下方法对象：

```c
0  +[XXObject load]
1  call_class_loads()
2  call_load_methods
3  load_images
4  dyld::notifySingle(dyld_image_states, ImageLoader const*)
11 _dyld_start
```

追其源头，从 `_dyld_start` 开始探究。**dyld(The Dynamic Link Editor)**是 Apple 的动态链接库，系统内核做好启动程序的初始准备后，将其他事务交给 dyld 负责。对于 dyld 这里不再细究，在以后对于动态库的学习时进行研究。

在研究 `load_images` 方法之前，先来研究一下什么是 **images**。**images**表示的是二进制文件（可执行文件或者动态链接库.so文件）编译后的符号、代码等。所以 `load_images` 的工作是**传入处理过后的二进制文件并让 `Runtime` 进行处理**，并且每一个文件对应一个抽象实例来负责加载，这里的实例是 `ImageLoader`，我们从调用栈的方法 4 可以清楚的看到参数类型：

```c
dyld::notifySingle(dyld_image_states, ImageLoader const*)
```

`ImageLoader` 处理二进制文件的时机是在 `main` 入口函数以前，它在加载文件时主要做两个工作：

* 在程序运行时它先将动态链接的 image 递归加载 （也就是上面测试栈中一串的递归调用的时刻）
* 再从可执行文件 image 递归加载所有符号

## 简单了解 image

在 [你真的了解 load 方法么？](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/%E4%BD%A0%E7%9C%9F%E7%9A%84%E4%BA%86%E8%A7%A3%20load%20%E6%96%B9%E6%B3%95%E4%B9%88%EF%BC%9F.md) 这篇文章中，*Draveness* 提供了一种断点发来打印出所有加载的镜像。

![](http://7xwh85.com1.z0.glb.clouddn.com/14838483024359.jpg)

这样可以将当前载入的 image 全部显示，我们展示的是 image 的 *path* 和 *slice* 信息。

```c
...
(const char *) $22 = 0x00007fff9c1f07a0 "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/DictionaryServices.framework/Versions/A/DictionaryServices"
(const mach_header *) $23 = 0x00007fff9c1f0000
(const char *) $24 = 0x00007fff9c51bb10 "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/SharedFileList.framework/Versions/A/SharedFileList"
(const mach_header *) $25 = 0x00007fff9c51b000
(const char *) $26 = 0x00007fff9ca70d90 "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
(const mach_header *) $27 = 0x00007fff9ca70000
(const char *) $28 = 0x00007fff5fbff870 "/Users/Desgard_Duan/Library/Developer/Xcode/DerivedData/objc-frsvxngqnjxvxwahvxtwjglbkjlt/Build/Products/Debug/debug-objc"
(const mach_header *) $29 = 0x0000000100000000
```

这里会传入很多的动态链接库 `.dylib` 以及官方静态框架 `.framework` 的 image，而 *path* 就是其对应的二进制文件的地址。在 `<mach-o/dyld.h>` 动态库头文件中，也为我们提供了查询所有动态库 image 的方法，在这里也简单介绍一下：

```c
#include <mach-o/dyld.h>
#include <stdio.h>

void listImages(){
    uint32_t i;
    uint32_t ic = _dyld_image_count();

    printf("Got %d images\n", ic);
    for (i = 0; i < ic; ++ i) {
        printf("%d: %p\t%s\t(slide: %p)\n",
               i,
               _dyld_get_image_header(i),
               _dyld_get_image_name(i),
               _dyld_get_image_vmaddr_slide(i));
    }
}

int main() {
    listImages();
    return 0;
}
```

我们可以通过系统库提供的接口方法，来深入学习官方的动态库情况。

![](http://7xwh85.com1.z0.glb.clouddn.com/14838490225420.jpg)

## 继续研究 load_images

```c
// load_images
// 执行 dyld 提供的并且已被 map_images 处理后的 image 中的 +load
// 锁定状态：runtimeLock写操作和 loadMethodLock 方法，保证线程安全
extern bool hasLoadMethods(const headerType *mhdr);
extern void prepare_load_methods(const headerType *mhdr);
void
load_images(const char *path __unused, const struct mach_header *mh) {
    // 没有查询到传入 Class 中的 load 方法，视为锁定状态
    // 则无需给其加载权限，直接返回
    if (!hasLoadMethods((const headerType *)mh)) return;
    
    // 定义可递归锁对象
    // 由于 load_images 方法由 dyld 进行回调，所以数据需上锁才能保证线程安全
    // 为了防止多次加锁造成的死锁情况，使用可递归锁解决
    recursive_mutex_locker_t lock(loadMethodLock);

    // 收集所有的 +load 方法
    {
        // 对 Darwin 提供的线程写锁的封装类
        rwlock_writer_t lock2(runtimeLock);
        // 提前准备好满足 +load 方法调用条件的 Class
        prepare_load_methods((const headerType *)mh);
        
    }

    // 调用 +load 方法 (without runtimeLock - re-entrant)
    call_load_methods();
}
```

重新回到 `load_images` 方法，`hasLoadMethods` 函数引起注意。其中为了查询 `load` 函数列表，会分别查询该函数在内存数据段上指定 section 区域是否有所记录。

```c
// 快速查询是否存在 +load 函数列表
bool hasLoadMethods(const headerType *mhdr) {
    size_t count;
    if (_getObjc2NonlazyClassList(mhdr, &count)  &&  count > 0) return true;
    if (_getObjc2NonlazyCategoryList(mhdr, &count)  &&  count > 0) return true;
    return false;
}
```

在 `objc-file.mm` 文件中存有以下定义：

```c
// 类似于 C++ 的模板写法，通过宏来处理泛型操作
// 函数内容是从内存数据段的某个区下查询该位置的情况，并回传指针
#define GETSECT(name, type, sectname)                                   \
    type *name(const headerType *mhdr, size_t *outCount) {              \
        return getDataSection<type>(mhdr, sectname, nil, outCount);     \
    }                                                                   \
    type *name(const header_info *hi, size_t *outCount) {               \
        return getDataSection<type>(hi->mhdr(), sectname, nil, outCount); \
    }

// 根据 dyld 对 images 的解析来在特定区域查询内存
GETSECT(_getObjc2ClassList,           classref_t,      "__objc_classlist");
GETSECT(_getObjc2NonlazyCategoryList, category_t *,    "__objc_nlcatlist");
```

在 Apple 的官方文档中，我们可以在 `__DATA` 段中查询到 `__objc_classlist` 的用途，主要是用在**访问 Objective-C 的类列表**，而 `__objc_nlcatlist` 用于**访问 Objective-C 的 `+load` 函数列表，比 `__mod_init_func` 更早被执行**。这一块对类信息的解析是由 dyld 处理时期完成的，也就是我们上文提到的 `map_images` 方法的解析工作。而且从侧面可以看出，Objective-C 的强大动态性，与 dyld 前期处理密不可分。

## 可递归锁

在 `load_images` 方法所在的 `objc-runtime-new.mm` 中，全局 `loadMethodLock` 是一个 `recursive_mutex_t` 类型的变量。这个是苹果公司通过 C 实现的一个互斥递归锁 Class，来解决多次上锁而不会发生死锁的问题。

其作用与 `NSRecursiveLock` 相同，但不是由 `NSLock` 再封装，而是通过 C 为 Runtime 的使用场景而写的一个 Class。更多关于线程锁的知识，强烈推荐 *bestswifter* 这篇博文 *[深入理解 iOS 开发中的锁](https://bestswifter.com/ios-lock/)*。

## 准备 +load 运行的从属 Class

```c
void prepare_load_methods(const headerType *mhdr) {
    size_t count, i;

    runtimeLock.assertWriting();
    
    // 收集 Class 中的 +load 方法
    // 获取所有的类的列表
    classref_t *classlist = 
        _getObjc2NonlazyClassList(mhdr, &count);
    for (i = 0; i < count; i++) {
        // 通过 remapClass 获取类指针
        // schedul_class_load 递归到父类逐层载入
        schedule_class_load(remapClass(classlist[i]));
    }
    
    // 收集 Category 中的 +load 方法
    category_t **categorylist = _getObjc2NonlazyCategoryList(mhdr, &count);
    for (i = 0; i < count; i++) {
        category_t *cat = categorylist[i];
        // 通过 remapClass 获取 Category 对象存有的 Class 对象
        Class cls = remapClass(cat->cls);
        if (!cls) continue; 
        // 对类进行第一次初始化，主要用来分配可读写数据空间并返回真正的类结构
        realizeClass(cls);
        assert(cls->ISA()->isRealized());
        // 将需要执行 load 的 Category 添加到一个全局列表中
        add_category_to_loadable_list(cat);
    }
}
```

`prepare_load_methods` 作用是为 load 方法做准备，从代码中可以看出 Class 的 load 方法是优先于 Category。其中在收集 Class 的 load 方法中，因为需要对 Class 关系树的根节点逐层遍历运行，在 `schedule_class_load` 方法中使用深层递归的方式递归到根节点，优先进行收集。


```c
// 用来规划执行 Class 的 load 方法，包括父类
// 递归调用 +load 方法通过 cls 指针以及
// 要求是 cls 指针的 Class 必须已经进行链接操作
static void schedule_class_load(Class cls) {
    if (!cls) return;
    // 查看 RW_REALIZED 是否被标记
    assert(cls->isRealized());
    
    // 查看 RW_LOADED 是否被标记
    if (cls->data()->flags & RW_LOADED) return;

    // 递归到深层（超类）运行
    schedule_class_load(cls->superclass);
    
    // 将需要执行 load 的 Class 添加到一个全局列表中
    add_class_to_loadable_list(cls);
    // 标记 RW_LOADED 符号
    cls->setInfo(RW_LOADED); 
}
```

在 `schedule_class_load` 中，Class 的读取方式是用 cls 指针方式，其中有很多内存符号位用来记录状态。`isRealized()` 查看的就是 `RW_REALIZED` 位，该位记录的是**当前 Class 是否初始化一个类的指标**。而之后查看的 `RW_LOADED` 是记录当前类的 `+load` 方法是否被被调用。

在存储静态表的方法中，方法对象会以指针的方式作为参数传递，然后用名为 `loadable_classes` 的静态类数组对即将运行的 load 方法进行存储，其下标索引 `loadable_classes_used` 为（从零开始的）全局量，并在每次录入方法后做自加操作实现索引的偏移。

由此可以看到，在 `prepare_load_methods` 方法中，Runtime 方法进行了 Class 和 Category 的筛选过滤工作，并且将即将执行的 load 方法以指针的形式组织成了一个线性表结构，为之后执行操作中打下基础。

## 通过函数指针让 load 方法跑起来

经过加载镜像、缓存类列表后，开始执行 `call_load_methods` 方法。

```c
void call_load_methods(void) {
    // 是否已经录入
    static bool loading = NO;
    // 是否有关联的 Category
    bool more_categories;
    loadMethodLock.assertLocked();

    // 由于 loading 是全局静态布尔量，如果已经录入方法则直接退出
    if (loading) return;
    loading = YES;
    // 声明一个 autoreleasePool 对象
    // 使用 push 操作其目的是为了创建一个新的 autoreleasePool 对象
    void *pool = objc_autoreleasePoolPush();

    do {
        // 重复调用 load 方法，直到没有
        while (loadable_classes_used > 0) {
            call_class_loads();
        }

        // 调用 Category 中的 load 方法
        more_categories = call_category_loads();

        // 继续调用，直到所有 Class 全部完成
    } while (loadable_classes_used > 0  ||  more_categories);
    // 将创建的 autoreleasePool 对象释放
    objc_autoreleasePoolPop(pool);
    // 更改全局标记，表示已经录入
    loading = NO;
}
```

其实 `call_load_methods` 由以上代码可知，仅是运行 load 方法的入口。其中最重要的方法 `call_class_loads` 会从一个待加载的类列表  `loadable_classes` 中寻找对应的类，并使用 `selector(load)` 的实现并执行。

```c
static void call_class_loads(void) {
    // 声明下标偏移
    int i;
    // 分离加载的 Class 列表
    struct loadable_class *classes = loadable_classes;
    // 调用标记
    int used = loadable_classes_used;
    loadable_classes = nil;
    loadable_classes_allocated = 0;
    loadable_classes_used = 0;
    
    // 调用列表中的 Class 类的 load 方法
    for (i = 0; i < used; i++) {
        // 获取 Class 指针
        Class cls = classes[i].cls;
        // 获取方法对象
        load_method_t load_method = (load_method_t)classes[i].method;
        if (!cls) continue;
        if (PrintLoading) {
            _objc_inform("LOAD: +[%s load]\n", cls->nameForLogging());
        }
        // 方法调用
        (*load_method)(cls, SEL_load);
    }
    // 释放 Class 列表
    if (classes) free(classes);
}
```

读完源码，也许会好奇为什么 `(*load_method)(cls, SEL_load);` 这一句可以调用 load 方法？

其实这是 C 中的**函数指针**基本概念。在这里我用一个简单的例子做个简要说明（如果没有看懂，需要补补基础了0.0）：

```c
#include <stdio.h>
#import <Foundation/Foundation.h>

void run() {
    printf("Hello World\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        void (*dy_run)() = run;
        (*dy_run)();
    }
    return 0;
}
```

其结果会发现执行了 `run` 方法，并输出了 `Hello World`。这里，我们通过一个 `void (*fptr)()` 类型的函数指针，将 `run` 函数获取出，并运行函数。实际上其中的工作是抓取 `run` 函数的地址并存储在指针变量中。我们通过指针运行对应的地址部分，其效果为执行了 `run` 函数。

返回方法中的 `load_method_t`，我们在全局位置发现了该类型的定义：

```c
typedef void(*load_method_t)(id, SEL);
```

`id` 参数可以传递一个类信息，这里是将 `cls` Class 的指针和 `SEL` 选择子作为参数传入。

至此完成了 load 方法的动态调用。

## 全局 Class 存储线性表数据结构

总结一下 Class 中 load 方法的全部流程，用流程图将其描述一下：

![](http://7xwh85.com1.z0.glb.clouddn.com/14844929413362.jpg)

下面来研究一下，存储 Class 的全局表数据结构是怎样的。

找到之前的 `add_class_to_loadable_list` 开始分析：

```c
void add_class_to_loadable_list(Class cls) {
    // 定义方法指针
    // 目的是构造函数指针
    IMP method;

    loadMethodLock.assertLocked();
    // 通过 cls 中的 getLoadMethod 方法，直接获得 load 方法体存储地址
    method = cls->getLoadMethod();
    // 没有 load 方法直接返回
    if (!method) return;     
    if (PrintLoading) {
        _objc_inform("LOAD: class '%s' scheduled for +load", 
                     cls->nameForLogging());
    }
    // 判断数组是否已满
    if (loadable_classes_used == loadable_classes_allocated) {
        // 动态扩容，为线性表释放空间
        loadable_classes_allocated = loadable_classes_allocated*2 + 16;
        loadable_classes = (struct loadable_class *)
            realloc(loadable_classes,
                              loadable_classes_allocated *
                              sizeof(struct loadable_class));
    }
    // 将 Class 指针和方法指针记录
    loadable_classes[loadable_classes_used].cls = cls;
    loadable_classes[loadable_classes_used].method = method;
    // 游标自加偏移
    loadable_classes_used++;
}
```

在记录过程中，可以看到其 Class 指针和方法指针的记录手段是通过构造 `loadable_classes` 这个类型的数组进行静态线性表记录。这个类型的数组其数据结构定义如下：

```c
typedef struct objc_class *Class;
struct loadable_class {
    Class cls;
    IMP method;
};
```

其 `objc_class` 结构笔者在*[用 isa 承载对象的类信息](http://www.desgard.com/isa/)*一文中有较为详细的介绍，这是对于 Class 的抽象。从此看出，全局 Class 存储线性表结构，内部记录的信息只有 Class 指针和方法指针，这已经足够了。

load 方法的调用情况至此已经全部清晰。思路梳理如下三大流程：

* Load Images: 通过 `dyld` 载入 image 文件，引入 Class。
* Prepare Load Methods: 准备 load 方法。过滤无效类、无效方法，将 load 方法指针和所属 Class 指针收集至全局 Class 存储线性表 `loadable_classes` 中，其中会涉及到自动扩展空间和父类优先的递归调用问题。
* Call Load Methods: 根据收集到的函数指针，对 load 方法进行动态调用。进一步过滤无效方法，并记录 log 日志。


## Load 方法作用

`load` 方法是我们在开发中最接近 app 启动的可控方法。即在 app 启动以后，入口函数 `main` 之前。

由于调用有着 *non-lazy* 属性，并且在运行期只调用一次，于是我们可以使用 `load` 独有的特性和调用时机来尝试 Method Swizzling。当然因为 load 调用时机过早，并且当多个 Class 没有关联（继承与派生），我们无法知道 Class 中 load 方法的优先调用关系，所以一般不会在 load 方法中引入其他的类，这是在开发当中需要注意的。


## 参考文献

[你真的了解 Objective-C 中的load 方法么？](https://github.com/Draveness/iOS-Source-Code-Analyze/blob/master/contents/objc/%E4%BD%A0%E7%9C%9F%E7%9A%84%E4%BA%86%E8%A7%A3%20load%20%E6%96%B9%E6%B3%95%E4%B9%88%EF%BC%9F.md)

[NSObject +load and +initialize - What do they do?](http://stackoverflow.com/questions/13326435/nsobject-load-and-initialize-what-do-they-do)

[Objective-C Class Loading and Initialization](https://www.mikeash.com/pyblog/friday-qa-2009-05-22-objective-c-class-loading-and-initialization.html)

[+load VS +initialize](https://medium.com/@kostiakoval/load-vs-initialize-a1b3dc7ad6eb#.5fhb7mfip)

[Objective-C +load vs +initialize](http://blog.leichunfeng.com/blog/2015/05/02/objective-c-plus-load-vs-plus-initialize/)

[Objective-C: What is a lazy class?](http://stackoverflow.com/questions/15315668/objective-c-what-is-a-lazy-class)


> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。
