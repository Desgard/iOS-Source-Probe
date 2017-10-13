> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/2016/08/11/copy/)


# 浅谈 block - clang 改写后的 block 结构

这几天为了巩固知识，从 iOS 的各个知识点开始学习，希望自己对每一个知识理解的更加深入的了解。这次来分享一下 block 的学习笔记。

## block 简介

block 被当做扩展特性而被加入 GCC 编译器中的。自从 OS X 10.4 和 iOS 4.0 之后，这个特性被加入了 Clang 中。因此我们今天使用的 block 在 C、C++、Objective-C 和 Objective-C++ 中均可使用。

对于 block 的语法，只放一张图即可。在之后的 block 系列文章中会详细说明其用法。



![img_1.jpg](http://upload-images.jianshu.io/upload_images/208988-0e4c759180531b28.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



## C 中的 block

说起 Xcode 的默认编译器 clang ，不得不提及 clang 在整个 编译 - 链接 过程中所起到的作用。在编译期， clang 首先对 Objective-C 代码做分析检查，确保代码中没有任何明显的错误，然后将其转换成为低级的类汇编代码，即我们经常说的**中间码**。

在学习 Objective-C 中的 block ，会经常使用的 clang 的 `-rewrite-objc` 命令来将 block 的语法转换成C语言的 struct 结构，从而供我们学习参考。

先从最简单的C语言中的 block 看起：

```c
#include <stdio.h>

void (^outside)(void) = ^{
    printf("Hello block!\n");
};

int main () {
    outside();
    return 0;
}
```

然后使用 `clang -rewrite-objc` 命令对 `blockTest.c` 进行 block 语法转换，得到 blockTest.cpp 这个文件。


![img_2.jpg](http://upload-images.jianshu.io/upload_images/208988-b590f135364802bb.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


在精简代码后，选取出主要关注的代码片段。

```c
struct __block_impl {
    void *isa;
    int Flags;
    int Reserved;
    void *FuncPtr;
};

struct __outside_block_impl_0 {
    struct __block_impl impl;
    struct __outside_block_desc_0* Desc;
    __outside_block_impl_0(void *fp, struct __outside_block_desc_0 *desc, int flags=0) {
        impl.isa = &_NSConcreteGlobalBlock;
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};

static void __outside_block_func_0(struct __outside_block_impl_0 *__cself) {
    printf("Hello block!\n");
}

static struct __outside_block_desc_0 {
    size_t reserved;
    size_t Block_size;
} __outside_block_desc_0_DATA = { 
    0, 
    sizeof(struct __outside_block_impl_0)
};

int main () {
    ((void (*)(__block_impl *))((__block_impl *)outside)->FuncPtr)((__block_impl *)outside);
    return 0;
}

```

代码可能有些难懂，逐一来分析。

```c
static void __outside_block_func_0(struct __outside_block_impl_0 *__cself) {
    printf("Hello block!\n");
}
```

这个函数应该是和源代码最相近的部分。并且，源代码中的 block 名被重新组合成一种新的字符串形式，而生成了这个函数的函数名。在参数上发现其实这个参数名又是一种新的字符串组合形式（`__xxx_block_impl_y`：这里的 xxx 是 **block 名称**，y 是**该函数出现的顺序值**）。

继续来看看参数 `__cself` 的声明：

```c
struct __outside_block_impl_0 {
    struct __block_impl impl;
    struct __outside_block_desc_0* Desc;
    
    // 构造函数
    __outside_block_impl_0(void *fp, struct __outside_block_desc_0 *desc, int flags=0) {
        impl.isa = &_NSConcreteGlobalBlock;
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
    }
};
```

第一个成员`impl`，是 __block_impl 类型，结构体在生成文件中也是出现的：

```c
struct __block_impl {
    void *isa;
    int Flags;
    int Reserved;
    void *FuncPtr;
};
```

* isa指针：指向一个类对象。在非 GC 模式下有三种类型：`_NSConcreteStackBlock`、`_NSConcreteGlobalBlock`、`_NSConcreteMallocBlock`。
* Flags：block 的负载信息（引用计数和类型信息），按位存储。在下面有详细说明。
* Reserved：保留变量。
* FuncPtr：指向 block 函数地址的指针。

在 runtime 的源码中，对于 Flags 的枚举要比文档中描述的更加详细，其定义如下。

```c
enum {
    BLOCK_DEALLOCATING =      (0x0001),  // runtime
    BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    BLOCK_NEEDS_FREE =        (1 << 24), // runtime
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
    BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ code
    BLOCK_IS_GC =             (1 << 27), // runtime
    BLOCK_IS_GLOBAL =         (1 << 28), // compiler
    BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if !BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE  =    (1 << 30)  // compiler
};
```

在 clang 的官方文档中，有这么一句话：

> The flags field is set to zero unless there are variables imported into the Block that need helper functions for program level `Block_copy()` and `Block_release()` operations, in which case the (1<<25) flags bit is set.

也就是说，一般情况下，一个 block 的 flags 成员默认设置为 0。如果当 block 需要 `Block_copy()` 和 `Block_release` 这类拷贝辅助函数，则会设置成 `1 << 25` ，也就是 **BLOCK_HAS_COPY_DISPOSE** 类型。可以搜索到大量讲述 `Block_copy` 方法的博文，其中涉及到了 **BLOCK_HAS_COPY_DISPOSE** 。

总结一下枚举类的用法，前 16 位即起到标记作用，又可记录引用计数：

* **BLOCK_DEALLOCATING**：释放标记。一般常用 **BLOCK_NEEDS_FREE** 做 位与 操作，一同传入 Flags ，告知该 block 可释放。
* **BLOCK_REFCOUNT_MASK**：一般参与判断引用计数，是一个可选用参数。
* **BLOCK_NEEDS_FREE**：通过设置该枚举位，来告知该 block 可释放。意在说明 block 是 heap block ，即我们常说的 **_NSConcreteMallocBlock** 。
* **BLOCK_HAS_COPY_DISPOSE**：是否拥有拷贝辅助函数（a copy helper function）。
* **BLOCK_HAS_CTOR**：是否拥有 block 析构函数（dispose function）。
* **BLOCK_IS_GC**：是否启用 GC 机制（Garbage Collection）。
* **BLOCK_HAS_SIGNATURE**：与 **BLOCK_USE_STRET** 相对，判断是否当前 block 拥有一个签名。用于 runtime 时动态调用。

我们返回结构体 `__outside_block_impl_0` 继续看第二个成员 Desc 指针。以下是 `__outside_block_desc_0` 结构体声明。

```c
static struct __outside_block_desc_0 {
    size_t reserved;
    size_t Block_size;
} __outside_block_desc_0_DATA = { 
    0, 
    sizeof(struct __outside_block_impl_0)
};
```

其中两个成员也可以从名字看出，描述的是 block 的预留区空间和 block 的大小。其中`size_t`类型在64位环境下应为`long unsigned int`，该宏定义在 C标准库 的 **stddef.h** 中。`__outside_block_desc_0_DATA` 是该结构体类型的环境量，使用成员对齐方式进行快捷构造。

再来看最重要的部分，即 `__outside_block_impl_0` 的构造函数。

```c
// 构造函数
__outside_block_impl_0(void *fp, struct __outside_block_desc_0 *desc, int flags=0) {
   impl.isa = &_NSConcreteGlobalBlock;
   impl.Flags = flags;
   impl.FuncPtr = fp;
   Desc = desc;
}
```

这里的所有过程除了 &_NSConcreteGlobalBlock 以外都比较好理解。先跳过这部分，放在文章最后进行分析。继续看一下入口函数 main()。

```c
int main () {
    ((void (*)(__block_impl *))((__block_impl *)outside)->FuncPtr)((__block_impl *)outside);
    return 0;
}
```

去掉强制转换部分，增强可读性：

```c
outside -> FuncPtr(outside);
```

也就是说，在执行我们定义的 block 的时候，会访问 impl 的 FuncPrt 这个函数指针。而在初始化（析构）时，这个函数会被指向 block 的执行函数体，也就是一开始分析的 `__outside_block_func_0` 方法。并且传入自身为参数。所以上文所提及的 `__cself` 参数，其实可以理解为面向对象中的**所属对象**，在 C++ 中我们常用 this 指针描述；而在 Objective-C 中，常常使用 self 。

写到这里，笔者有一些很有意思的联想。在 Objective-C 的设计中，为了突出对象与方法间的所属关系，经常会传递一个指针作为参数。例如在许多 Foundation 框架中的 Delegate 方法，第一个参数往往是委托方法的发起者本身。

最后再来看一下之前略过的 _NSConcreteGlobalBlock 。

对于任意一个对象的 isa 指针，其指向的对象是自身的类对象；而类对象的 isa 指针，指向的是元类（meta class）。而 block 虽然也是对象，但其结构是异于 NSObject 的。最新版本的 object 结构如下：

```c
struct objc_class : objc_object {
    // Class ISA;
    Class superclass;
    cache_t cache;             // formerly cache pointer and vtable
    class_data_bits_t bits;    // class_rw_t * plus custom rr/alloc flags
}
```

![img_3.png](http://upload-images.jianshu.io/upload_images/208988-26fce38e44961829.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



其中 object 的 isa 指针是从 objc_objcet 中继承而来的。而 block 为了模拟 object 结构，也用到了 isa 对其进行了分类。其中 _NSConcreteGlobalBlock 就是其中之一。

关于 block 类型将会在 block 系列其他文中介绍，这里由于我们的 block 是处在全局位置，所以其类型为 _NSConcreteGlobalBlock。

在学习 C 中的 block ，通过 clang 的语义转换将 block 语法使用 C 语言描述，使得我们更进一步的深入学习 block 的内部实现。

## 对于 clang -rewrite-objc 一种误区

很多时候，会想当然的认为，在编译期，clang 对代码进行语义判断之后，会像 `-rewrite-objc` 一样对代码进行转译成 C 语言，进而转换成中间码。但是，该命令并**不能代表编译后所执行的代码**。

在巧哥很久之前[谈Objective-C Block的实现](http://blog.devtang.com/2013/07/28/a-look-inside-blocks/)的文中，有这么一个代码片段：

```c
#include <stdio.h> 
 
int main() { 
    ^{ printf("Hello, World!\n"); } (); 
    return 0; 
} 
```

在使用 `-rewrite-objc` 进行语法转换后，所显示的 block 类型为 _NSConcreteStackBlock 。而根据我们对于 block 的认知，当 block 没有引用外部的变量对象时，其类型应为 _NSConcreteGlobalBlock。难道，clang 对于 Objective-C 中的 block 和 C 中的 block 处理，会有差异吗？其实不是的，我们来做这个实验：

```c
#include <stdio.h>

void (^outside)(void) = ^(void) {
    printf("Hello, block!\n");
};

int main() {
    void (^inside)(void) = ^(void) {
        printf("Hello, block!\n");
    };
    printf("outside: %p\n", outside);
    printf("inside:  %p\n", inside);

    return 0;
}
```

```c
outside: 0x10d48e040
inside:  0x10d48e080
```

从输出结果上看，两个 block 被存储在同一区域，也就是 .data 常量区。



![img_4.jpg](http://upload-images.jianshu.io/upload_images/208988-8deb7e7cc8475e58.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



可是在 main 函数内声明的 block 类型，通过 `clang -rewrite-objc` 工具转换后仍为 _NSConcreteStackBlock 栈存储 block 类型。从这个侧面，可以明白其实 clang 对语法的解释转换，**不一定出现在编译过程中**。而在编译期间转换成中间码的过程中，在新版本的 clang 编译器已经不需要解释成c的语法进行过度，从而翻译成中间码。而是，在语法检测后，直接转至中间码，提交至 llvm 进行链接处理。

所以，通过 `clang -rewrite-objc` 命令，仅将扩展语法通过可读性更高的 C 语法进行改写，而不是编译期中的子编译过程。我们仅仅通过他来了解 block 真正的结构就已经足够了。

## 尾声

这篇文章讲述了 block 的结构以及指向 block 函数体的具体方式。在以后的 block 系列学习笔记中，还会继续记录 block 类型、 block 使用等相关知识。

---



## 参考资料

[A look inside blocks (Block_copy)](http://www.galloway.me.uk/2013/05/a-look-inside-blocks-episode-3-block-copy/)

[clang官方文档：block 扩展语法](http://clang.llvm.org/docs/BlockLanguageSpec.html)

> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。

