> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](http://www.desgard.com/block2/)


# 浅谈 block - 截获变量方式

本文会通过 clang 的 `-rewrite-objc` 选项来分析 block 的 C 转换源代码。其分析方式在该系列上一篇有详细介绍。请先阅读 *[浅谈 block（1） - clang 改写后的 block 结构](https://desgard.com/block1/)* 。

## 截获自动变量

首先需要做代码准备工作，我们编写一段 block 引用外部变量的 c 代码。

![7E32C4CC-DE35-469E-8EC1-C20BCAE4CD0](http://7xwh85.com1.z0.glb.clouddn.com/7E32C4CC-DE35-469E-8EC1-C20BCAE4CD0C.png)

编译运行成功后，使用 `-rewrite-objc` 进行改写。

```shell
clang -rewrite-objc block.c
```

简化代码后，得到以下主要代码：

```objc
struct __main_block_impl_0 {
	struct __block_impl impl;
	struct __main_block_desc_0* Desc;
	char *str;
	__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, char *_str, int flags=0) : str(_str) {
		impl.isa = &_NSConcreteStackBlock;
		impl.Flags = flags;
		impl.FuncPtr = fp;
		Desc = desc;
	}                                                                                                                                                                                                      
};

static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
	char *str = __cself->str; // bound by copy
	printf("%s\n", str);
}

static struct __main_block_desc_0 {
	size_t reserved;
	size_t Block_size;
} __main_block_desc_0_DATA = { 
	0, 
	sizeof(struct __main_block_impl_0)
};

int main() {
	char *str = "Desgard_Duan";
	void (*block)() = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, str));
	((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
	return 0;
}

```

与上一篇转换的源码不同的是，block 语法表达中的变量作为成员添加到了 `__main_block_func_0` 结构体中。

```c
struct __main_block_impl_0 {
	struct __block_impl impl;
	struct __main_block_desc_0* Desc;
	char *str; // 外部引用变量
}
```

并且，在该结构体中的应用变量类型与外部的类型完全相同。在初始化该结构体实例的构造函数也自然会有所差异：

```c
void (*block)() = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, str));
```

去掉强转语法简化代码：

```c
void (*block)() = &__main_block_impl_0(__main_block_func_0, &__main_block_desc_0_DATA, str);
```

在构造时，除了要传递自身(self) `__main_block_func_0` 结构体，而且还要传递 block 的基本信息，即 reserved 和 size 。这里传递了一个全局结构体对象 `__main_block_desc_0_DATA` ，因为他是为 block 量身设计的。最后在将引用值参数传入构造函数中，以便于构造带外部引用参数的 block。

进入构造函数后，发现了含有冒号表达的构造语法：

```c
__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, char *_str, int flags=0) : str(_str) {
	impl.isa = &_NSConcreteStackBlock;
	impl.Flags = flags;
	impl.FuncPtr = fp;
	Desc = desc;
}
```

其实，冒号表达式是 C++ 中的一个固有语法。这是显示构造的方法之一。另外还有一种构造显示构造方式，其语法较为繁琐，即使用 this 指针构造。（关于 C++ 构造函数，可以学习 msdn 文档 *[构造函数 (C++)](https://msdn.microsoft.com/zh-cn/library/s16xw1a8.aspx)* ）

之后的代码与前一篇分析相同，不再讨论。

通过整个构造 block 流程分析，我们发现当 block 引用外部对象时，会在结构体内部新建立一个成员进行存储。此处我们使用的是 char* 类型，而在结构体中所使用的 char* 是结构体的成员，所以可以得知：**block 引用外部对象时候，不是简单的指针引用（浅复制），而是一种重建（深复制）方式**（括号内外分别对于基本数据类型和对象分别描述）**）**。所以如果在 block 中对外部对象进行修改，无论是值修改还是指针修改，自然是没有任何效果。

## 引入 __block 关键字对截取变量一探究竟

上文中的 block 所引用的外部成员是一个字符型指针，当我们在 block 内部对其修改后，很容易的想到，会改变该指针的指向。而当 block 中引用外部变量为常用数据类型会有些许的不同：

我们来看这个例子 (这是来自 *Pro multithreading and memory management for iOS and OS X* 2.3.3 一节的例子)：

```c
int val = 0;
void (^blk)(void) = ^{val = 1};
```

执行代码后会报 error ：

```bash
error: variable is not assignable (missing __block type specifier)
    void (^blk)(void) = ^{val = 1};
```

上述书中对此情况是这样解释的：

> block 中所使用的被截获自动变量如同“带有自动变量值的匿名函数”，仅截获自动变量的值。 block 中使用自动变量后，在 block 的结构体实力中重写该自动变量也不会改变原先截获的自动变量。

这应该是 clang 对 block 的引用外界局部值做的保护措施，也是为了维护 C 语言中的作用域特性。既然谈到了作用域，那么是否可以使用显示声明存储域类型从而在 block 中修改该变量呢？答案是可以的。当 block 中截取的变量为静态变量（static），使用下例进行试验：

```c
int main() {
	static int static_val = 2;
	void (^blk)(void) = ^{
		static_val = 3;
	};
}
```

装换后的代码：

```c
struct __main_block_impl_0 {
	struct __block_impl impl;
	struct __main_block_desc_0* Desc;
	int *static_val;
	__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, int *_static_val, int flags=0) {
		impl.isa = &_NSConcreteStackBlock;
		impl.Flags = flags;
		impl.FuncPtr = fp;
		Desc = desc;
	}
};

int main() {
	static int static_val = 2;
	void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_
	return 0;
 }
```

会发现在构造函数中使用的静态指针 `int *_static_val` 对其进行访问。将静态变量 `static_val` 的指针传递给 `__main_block_impl_0` 结构体的构造函数并加以保存。通过指针进行作用域拓展，是 C 中很常见的思想及做法，也是超出作用域使用变量的最简单方法。

那么我们为什么在引用自动变量的时候，不使用该自动变量的指针呢？是应为在 block 截获变量后，原来的自动变量已经废弃，因此block 中超过变量作用域从而无法通过指针访问原来的自动变量。

为了解决这个问题，其实在 block 扩展中已经提供了方法（[官方文档](http://clang.llvm.org/docs/BlockLanguageSpec.html#the-block-storage-qualifier)）。即使用 `__block` 关键字。

`__block` 关键字更准确的表达应为 *__block说明符(__block storage-class-specifier)* ，用来描述存储域。在 C 语言中已经存有如下存储域声明关键字：

* typedef：常用在为数据类型起别名，而不是一般认识的存储域声明关键字作用。但在归类上属于存储域声明关键字。
* extern：限制标示，限制定义变量在所有模块中作为全局变量，并只能被定义一次。
* static：静态变量存储在 .data 区。
* auto：自动变量存储在栈中。
* register：约束变量为单值，存储在CPU寄存器内。

`__block` 关键字类似于 `static`、`auto`、`register`，用于将变量存于指定存储域。来分析一下在变量声明前增加 `__block` 关键字后 clang 对于 block 的转换动作。

```c
__block int val = 1;
void (^blk)(void) = ^ {
   val = 2;
};
```

```c
// 要点 1：__block 变量转换结构
struct __Block_byref_val_0 {
	void *__isa;
	__Block_byref_val_0 *__forwarding;
	int __flags;
	int __size;
	int val;
};

struct __main_block_impl_0 {
	struct __block_impl impl;
	struct __main_block_desc_0* Desc;
	__Block_byref_val_0 *val; // by ref
	__main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, __Block_byref_val_0 *_val, int flags=0) : val(_val->__forwarding) {
		impl.isa = &_NSConcreteStackBlock;
		impl.Flags = flags;
		impl.FuncPtr = fp;
		Desc = desc;
	}
};

static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
	__Block_byref_val_0 *val = __cself->val; // bound by ref
	// 要点 2：__forwarding 自环指针存在意义
	 (val->__forwarding->val) = 2;
}

static struct __main_block_desc_0 {
	size_t reserved;	
	size_t Block_size;
	// 要点 3：copy/dispose 方法内部实现
	void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
	void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 
	0, 
	sizeof(struct __main_block_impl_0), 
	__main_block_copy_0, 
	__main_block_dispose_0
	};
	
int main() {
    __attribute__((__blocks__(byref))) __Block_byref_val_0 val = {
    	(void*)0,
	    (__Block_byref_val_0 *)&val, 
	    0, 
	    sizeof(__Block_byref_val_0), 1
    };
    void (*blk)(void) = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, (__Block_byref_val_0 *)&val, 570425344));
    return 0;
}
```

发现核心代码部分有所增加，我们先从入口函数看起。

```c
__Block_byref_val_0 val = {
	(void*)0,
    (__Block_byref_val_0 *)&val, 
    0, 
    sizeof(__Block_byref_val_0), 
    1
};
```

原先的 val 变成了 `__Block_byre_val_0` 结构体类型变量。并且这个结构体的定义是之前未曾见过的。并且我们将 val 初始化的数值 1，也出现在这个构造中，说明该结构体持有原成员变量。

```c
struct __Block_byref_val_0 {
	void *__isa;
	__Block_byref_val_0 *__forwarding;
	int __flags;
	int __size;
	int val;
};
```

在 `__block` 变量的结构体中，除了有指向类对象的 `isa` 指针，对象负载信息 `flags`，大小 `size`，以及持有的原变量 `val`，还有一个自身类型的 `__forwarding` 指针。从构造函数中，会发现一个有趣的现象，**`__forwarding` 指针会指向自身，形成自环**。后面会详细介绍它。

而在 block 体执行段，是这样定义的。

```c
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
	__Block_byref_val_0 *val = __cself->val; // bound by ref
	 (val->__forwarding->val) = 2;
}
```

第一步中获得 val 的方法和 block 中引用外部变量的方式是一致的，通过 self 来获取变量。而对于外部 __block 变量赋值的时候，这种写法引起了我们的注意：`(val->__forwarding->val) = 2;` ，这样做的目的何在，在后文会做出分析。

## __block 变量结构

![__block结构](http://7xwh85.com1.z0.glb.clouddn.com/__block%E7%BB%93%E6%9E%84.png)

当 block 内部引用外部的 __block 变量，会使用以上结构对 __block 做出转换。另外，该结构体并不声明在 `__main_block_impl_0` block 结构体中，是因为这样可以对多个 block 引用 __block 情况下，达到复用效果，从而节省不必要的空间开销。

```c
__block int val = 0;
void (^blk1)(void) = ^{val = 1;};
void (^blk2)(void) = ^{val = 2;};
```

只观察入口方法：

```c
__Block_byref_val_0 = {0, &val, 0, sizeof(__Block_byref_val_0), 10};
blk1 = &__main_block_impl_0(__main_block_func_0
									, &__main_block_desc_0_DATA
									, &val
									, 0x22000000);
									
blk2 = &__main_block_impl_0(__main_block_func_1
									, &__main_block_desc_1_DATA
									, &val
									, 0x22000000);
```

发现 val 指针被复用，使得两个 block 同时使用一个 __block 只需要对其结构声明一次即可。

## 接触 Objective-C 语言环境下的 block

通过两篇文的 block 的结构转换，我们发现其实 block 的实质是一个*对象 (Object)*，从封装成结构体对象，再到 isa 指针结构，都是明显的体现。对于 __block 也是如此，在转换后将其封装成了 __block 结构体类型，以对象方式处理。

带着 C 代码中的 block 扩展转换规则开始进入 Objective-C block 的学习。首先需要知道 block 的三个类型。

| 类型       |    对象存储域 | 地址单元 |
| :-------- | --------:| ---- |
| _NSConcreteStackBlock  | 栈 | 高地址 |
| _NSConcreteMallocBlock  | 堆 |  |
| _NSConcreteGloalBlock | 静态区(.data)  | 低地址 |

在上一篇文中的末尾部分，简单的说了一下全局静态的存储问题。这里再一次强调， `_NSConcreteGloalBlock` 的 block 会在一下两种情况下出现（与 clang 转换结果不大相同）：

* 全局变量位置
* block 中不引用外部变量

而在其他情况下，基本上 block 的类型都为 _NSConcreteStackBlock 。但是在栈上的 block 会受到作用域的限制，一旦所属的变量作用域结束，该 block 就会被释放。由此，引出了 _NSConcreteMallocBlock 堆 block 类型。

block 提供了将 block 和 __block 变量从栈上复制到堆上的方法来解决这个问题。将配置在站上的 block 复制到堆上，这样可以保证在 block 变量作用域结束后，堆上仍旧可访问。

__block 变量通过 __forwarding 可以无论在堆上还是栈上都能正常访问。当 block 存储在堆上的时候，对应的栈上 block 的 __forwarding 成员会断开自环，而指向堆上的 block 对象。这也就是 __forwarding 指针存在的真实用意。

![block_forwarding](http://7xwh85.com1.z0.glb.clouddn.com/block_forwarding.png)


在复制到堆的过程中，__forwarding 指针是如何更改指向的？这个问题在下一篇中进行介绍。这篇文主要讲述了 __block 变量在 block 中的结构，以及如何获取外部变量，并可以对其修改的详细过程，希望有所收获。



> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。

