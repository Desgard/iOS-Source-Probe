> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](http://www.desgard.com/isa/)

# 用 isa 承载对象的类信息

*Effective Objective-C 2.0 - 52 Specific Ways to Improve Your iOS and OS X Programs* 一书中，*tip 14* 中提到了，*运行时检查对象类型* 的 **自省** (Introspection) 特性。那么先来说说 **自省** 和 **反射** 的定义是什么。

## 自省与反射的简单认识

第一次听说这两个概念，是在 *Thinking in Java (4th Edition)* 中的，而深入学习他们则是在 Python 语言的学习中，以下我用 Python 来举例说明。

> wikipedia: In computer science, reflection is the ability of a computer program to examine and modify its own structure and behavior (specifically the values, meta-data, properties and functions) at runtime.

反射(Reflection) 是指计算机程序可以在运行时动态监测并修改它自己的结构和行为，比如值、元数据、属性和函数等的能力。通过反射，可以在运行时动态监测、生成、修改自己实际执行的等效代码。

```python
class HelloClass(object):
    def __init__(self, method):
        self.method = method
        print('You are calling me from ' + self.method)

    def say_hello(self):
        print("Hello -- From: " + self.method)
        print()

# Normal
obj = HelloClass('Normal')
obj.say_hello()

# Reflection
class_name = "HelloClass"
method = "say_hello"
obj = globals()[class_name]('Reflection')
getattr(obj, method)()
```

```
You are calling me from Normal
Hello -- From: Normal
()
You are calling me from Reflection
Hello -- From: Reflection
()
```

两种方法可以达到同样的效果。但是，第一种方法是我们所说的常规方法，创建 HelloClass 这个 class 的一个实例，然后调用其中的方法。第二种我们用到了反射机制，通过 `globals()` 这个字典中来查找 `HelloClass` 这个类，并加以参数进行实例化于 `obj`，之后通过 `getattr` 函数获得 `say_hello` 方法，传参调用。

反射的好处在于，`class_name` 和 `method` 变量的值可以在运行时获取或者修改，这样可以动态地改变程序的行为。

> wikipedia: In computing, type introspection is the ability of a program to examine the type or properties of an object at runtime.

自省(Introspection) 是程序在运行时检测自己的某个对象的类型或者属性、方法的能力。例如在 Python 中的 `dir` 方法。

```python 
class HelloClass(object):

    def __init__(self, method):
        self.method = method
        print('You are calling me from ' + self.method)

    def say_hello(self):
        print("Hello -- From: " + self.method)
        print()

obj = HelloClass('Normal')
obj_msg = dir(obj)

for x in obj_msg:
    print (x)
```

```python
__class__
__delattr__
__dict__
__doc__
__format__
__getattribute__
__hash__
__init__
__module__
__new__
__reduce__
__reduce_ex__
__repr__
__setattr__
__sizeof__
__str__
__subclasshook__
__weakref__
method
say_hello
```

通过 `dir()` 函数从而做到自省，它可以返回某个对象的所有属性、方法等列表。

通过上述简单描述，我们大概知道了反射其实是包含着自省能力的，不仅可以获取到对象的各种属性信息，而且还可以动态修改自身的结构和行为。

## objc_class 结构

在 ObjC 中，也支持在运行时检查对象类型这一操作，并且这个特性是内置于 Foundation 框架的 NSObject 协议中的。凡是公共基类(Common Root Class)，即 NSObject 或 NSProxy ，继承而来的对象都要遵循此协议。

虽然 ObjC 支持自省这一特性，就一定会对 Class 信息做存储。这里我们便要引出 isa 指针。倘若对 ObjC 有一定的学习基础，都会知道 **Objective-C 对象都可以通过 clang 进行 c 的语法格式转换，从而以 struct 来描述**。所有的对象中都有一个 `isa` 指针，其含义是： it **is a** object! 而在最新的 runtime 库中，其 isa 指针的结构已经发生了变化。

以下代码均参考 runtime 版本为 [objc4-680.tar.gz](http://opensource.apple.com/tarballs/objc4/)。

```c
struct objc_object {
private:
    isa_t isa;
}
```

会发现在 objc_object 这个基类中只有一个成员，即 isa_t 联合体(union) 类型的 isa 成员。而对于类对象的定义，可以从 objc_class 查看其结构：

```c
struct objc_class : objc_object {
    // Class ISA;
    Class superclass; 	// 父类引用
    cache_t cache;		// 用来缓存指针和虚函数表
    class_data_bits_t bits; // class_rw_t 指针加上 rr/alloc 标志
}
```

> runtime 的开源作者怕学习者不知道 isa 已经从 objc_object 继承存在，用注释加以提示。

其实，开发中所使用的类和实例，都会拥有一个记录自身信息的 isa 指针，只是因为 runtime 从 objc_object 继承出的，所以不会显式看到。

![](http://7xwh85.com1.z0.glb.clouddn.com/objc_object_structure.png)


需要知道的是，class_data_bits_t 中存有 Class 的对应方法，具体如何存储，会在后续的文中记录。

## isa 优化下的信息记录

isa 是一个联合体类型，其结构如下：

```c
union isa_t {
    isa_t() { }
    isa_t(uintptr_t value) : bits(value) { }

    Class cls;
    uintptr_t bits;
    struct {
        uintptr_t indexed           : 1;
        uintptr_t has_assoc         : 1;
        uintptr_t has_cxx_dtor      : 1;
        uintptr_t shiftcls          : 33; 
        uintptr_t magic             : 6;
        uintptr_t weakly_referenced : 1;
        uintptr_t deallocating      : 1;
        uintptr_t has_sidetable_rc  : 1;
        uintptr_t extra_rc          : 19;
    };
};
```

> 该定义是在 `__arm64__` 环境下的 isa_t 联合体结构。因为 iOS 应用为 `__arm64__` 架构环境。

**可以看到在 isa_t 联合体中不仅仅表明了指向对象的地址信息，而且这个 64 位数据还记录了其 bits 情况以及该实例每一位保存的对象信息**。来验证一下（记住要使用真机调试， real device 和 simulator 的架构环境是有一定区别）：

```c
- (void)viewDidLoad {
    NSObject *object = [NSObject new];
    // 在 ARC 模式下，通过 __bridge 转换 id 类型为 (void *) 类型
    NSLog(@"isa: %p ", *(void **)(__bridge void *)object);
    static void *someKey = &someKey;
    objc_setAssociatedObject(object, someKey, @"Desgard_Duan", OBJC_ASSOCIATION_RETAIN);
    NSLog(@"isa: %p ", *(void **)(__bridge void *)object);
}
```

输出结果为：

```c
2016-09-25 23:01:44.257 isa: 0x1a1ae5a3ea1 
2016-09-25 23:01:44.257 isa: 0x1a1ae5a3ea3 
```

首先先来看一下这 64 个二进制位每一位的含义：

| 区域名 | 代表信息 |
| --- | --- |
| indexed |  0 表示普通的 `isa` 指针，1 表示使用优化，存储引用计数|
| has_assoc |  表示该对象是否包含 `associated object`，如果没有，则析构时会更快|
| has_cxx_dtor | 表示该对象是否有 C++ 或 ARC 的析构函数，如果没有，则析构时更快 |
| shiftcls | 类的指针 |
| magic | 固定值，用于在调试时分辨对象是否未完成初始化 |
| weakly_referenced | 表示该对象是否有过 weak 对象，如果没有，则析构时更快 |
| deallocating | 表示该对象是否正在析构 |
| has_sidetable_rc | 表示该对象的引用计数值是否过大无法存储在 isa 指针 |
| extra_rc | 存储引用计数值减一后的结果 |


将 16 进制的 `0x1a1ae5a3ea3` 转换成二进制。发现在 `has_assoc` 和 `index` 两个位都是 1 。根据代码我们可以知道我们手动为其设置了 `associated object`，所以以上的含义表是正确的。这里详细的再说一下 `indexed` 的含义。

![isa-bits](http://7xwh85.com1.z0.glb.clouddn.com/isa-bits.png)


## isa 初始化行为，indexed 以及 magic 段的默认值

`isa` 指针会通过 `initIsa` 来初始化。

```c
#define ISA_MASK        0x0000000ffffffff8ULL
#define ISA_MAGIC_MASK  0x000003f000000001ULL
#define ISA_MAGIC_VALUE 0x000001a000000001ULL


inline void  
objc_object::initInstanceIsa(Class cls, bool hasCxxDtor)  
{
	// initIsa 入口函数
	// 传入 Class 对象，是否为 isa 优化量，
    initIsa(cls, true, hasCxxDtor);
}

inline void  
objc_object::initIsa(Class cls, bool indexed, bool hasCxxDtor)  
{ 
    if (!indexed) {
    	// 如果没有使用 isa 优化，其内部只记录地址信息
        isa.cls = cls;
    } else {
    	// ISA_MAGIC_VALUE 为 bits（isa 信息）赋初值
    	// 注意在 arm64 下 mask 部分固定为 0x1a
        isa.bits = ISA_MAGIC_VALUE;
        // 是否拥有 C++ 中的析构函数
        isa.has_cxx_dtor = hasCxxDtor;
        // 由于使用了 isa 优化，所以第三位拥有其他信息
        // 需要将 cls 初始数据左移，保存在 shiftcls 对应位置
        isa.shiftcls = (uintptr_t)cls >> 3;
    }
}
```

在以上代码中，可以看到在一个 `isa_t` 结构中，magic 段是一个固定值，在 arm64 架构下其值为 `0x1a`，而在 x86 下则为 `0x1d`，笔者猜测这一位也有判断架构类型之意。而观察 isa 初始化的调用栈，可以发现是 `callAlloc` 函数进行调用。这段代码的解读，将放在以后的文中。

## ISA() 获取非 Tagged Pointer 对象

```c
#define ISA_MASK        0x0000000ffffffff8ULL

// 简单 isa 初始化方式
inline void 
objc_object::initIsa(Class cls)
{
    initIsa(cls, false, false);
}

inline void 
objc_object::initClassIsa(Class cls)
{
	// non-pointer isa 情况
    if (DisableIndexedIsa) {
        initIsa(cls, false, false);
    } else {
        initIsa(cls, true, false);
    }
}

inline void
objc_object::initProtocolIsa(Class cls)
{
    return initClassIsa(cls);
}

inline Class 
objc_object::ISA() 
{
    assert(!isTaggedPointer()); 
    // 与有效位全 1 码进行与运算来过滤非有效位
    return (Class)(isa.bits & ISA_MASK);
}
```

![ISA--](http://7xwh85.com1.z0.glb.clouddn.com/ISA--.png)

从中发现，其有效区域也就是 isa_t 中的 `shiftcls` 区域。而且这种掩码方式，也是从 isa_t 中查询信息的主要方式，再很多方法中可以看见类似的做法。

## isa 的主地址检索

无论在新旧版本的 Objective-C 中，都会有 isa 指针来记录类的信息。而在现在的 runtime 库中，由于 64 位的优势，使用联合体又增加了类信息记录的补充。而对于 isa 的主要部分，其记录的主要信息是什么呢？

在之前的一些文章中，笔者通过了 ObjC 的消息转发机制稍微提及了一些关于 isa 的知识，可以参考这篇文章 *[objc_msgSend消息传递学习笔记 - 对象方法消息传递流程](http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html)* 。 在消息传递的主要流程中，最重要的一个环节就是*快速查询 isa 操作 GetIsaFast* ，其中要继续的搜寻所属 Class 的方法列表（所有成员方法所对应的 Hash Table）。可见 isa 记录的地址信息和当前实例的 Class 有直接关系。

下面通过实验来验证我们的猜测：

```c
- (void)viewDidLoad {
    NSObject *object = [NSObject new];
    NSLog(@"isa: %p ", *(void **)(__bridge void *)object);
    
    NSObject *object_2 = [NSObject new];
    NSLog(@"isa: %p ", *(void **)(__bridge void *)object_2);
}
```

在真机上运行该代码片段，可以发现其输出的结果：

```c
2016-09-30 10:34:15.577813 isa: 0x1a1a96cbea1
2016-09-30 10:34:15.577897 isa: 0x1a1a96cbea1
```

在输出 isa 的指针后，可以发现其记录的值完全相等。并且再通过对其 isa 指向地址的 Class Name 输出，可知其 isa 指针是指向所属 Class 对象地址。这只是对于对象实例的 isa 指针而言。

至此我们可能会产生另外一个疑问：

> 既然 Objective-C 将所有的事物对象化，那么其所属 Class 也会拥有 isa 指针，那么所属 Class 的 isa 是如何规定指向问题的？

下面引出 *元类 meta-class* 的概念。

## Class 的 isa 指向：meta-class

在 Objective-C 中，每一个 Class 都会拥有一个与之相关联的   meta-class 。但是在业务开发中，可能永远不会接触，因为这个 Class 是用来记录一些类信息，而不会直接将其成员的属性接口暴露出来。下面来逐一探究一番（以下例子参考文章 *[What is a meta-class in Objective-C?](http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html)* ）：

```c
- (void)viewDidLoad {
    [super viewDidLoad];
    
    Class newClass = objc_allocateClassPair([NSError class], "RuntimeErrorSubclass", 0);
    class_addMethod(newClass, @selector(report), (IMP)ReportFunction, "v@:");
    objc_registerClassPair(newClass);
}

void ReportFunction(id self, SEL _cmd) {
    NSLog(@"This object is %p.",self);
    NSLog(@"Class is %@, and super is %@.",[self class],[self superclass]);
    Class currentClass = [self class];
    for( int i = 1; i < 5; ++i ) {
        NSLog(@"Following the isa pointer %d times gives %p", i, currentClass);
    }
    NSLog(@"NSObject's class is %p", [NSObject class]);
    NSLog(@"NSObject's meta class is %p",object_getClass([NSObject class]));
}
```

这段代码所做的事情是在 runtime 时期创建 `NSError` 的一个子类 `RuntimeErrorSubclass` 。`objc_allocateClassPair` 方法会创建一个新的 Class ，然后取出 Class 的对象，使用 `class_addMethod` 方法，为该 Class 添加方法，需要开发者传入添加方法的 Class 、方法名、实现函数、以及定义该函数返回值类型和参数类型的字符串。最后调用 `objc_registerClassPair` 对其进行注册即可。

> 要点：在调用 `objc_allocateClassPair` 方法增加新的 Class 的时候，可以调用 `class_addIvar` 增加成员属性和 `objc_registerClassPair` 增加成员方法。

```c
Class objc_allocateClassPair(Class superclass, const char *name, 
                             size_t extraBytes)
{
    Class cls, meta;

    rwlock_writer_t lock(runtimeLock);

    // 如果 Class 名重复则创建失败
    // 如果父类没有通过认证则创建失败
    if (getClass(name)  ||  !verifySuperclass(superclass, true/*rootOK*/)) {
        return nil;
    }

    // 为 cls 和 meta 分配空间
    cls  = alloc_class_for_subclass(superclass, extraBytes);
    meta = alloc_class_for_subclass(superclass, extraBytes);
	
	// 对 cls 和 meta 做指向判定
    objc_initializeClassPair_internal(superclass, name, cls, meta);

    return cls;
}
```

在 `objc_allocateClassPair` 方法可以说是 `objc_initializeClassPair_internal` 的方法入口，其主要的功能是 **根据 superclass 的信息和 Class 中的一些标记成员来确定 cls 和 meta 指针的指向，并调用 `addSubclass` 方法将其加入到 superclass 中**。

通过 `objc_i nitializeClassPair_internal` 方法中，调用 `meta -> initClassIsa();` 来初始化 isa 指针。下面通过 `objc_initializeClassPair_internal` 来看看 isa 指针和 meta 的初始化方式。

```c
// objc_initializeClassPair_internal 方法
// superclass: 父类指针
// name: 类名
// cls: 主类索引
// meta: metaclass 索引

// 解锁操作，写操作要求
runtimeLock.assertWriting();

// 只读结构 read only
// 分别声明 cls 和 meta 两个
class_ro_t *cls_ro_w, *meta_ro_w;

// 缓存初始化操作
cls->cache.initializeToEmpty();
meta->cache.initializeToEmpty();

// 数据设置操作
// data() -> ro 成员，与方法列表，属性，协议相关
cls->setData((class_rw_t *)calloc(sizeof(class_rw_t), 1));
meta->setData((class_rw_t *)calloc(sizeof(class_rw_t), 1));
cls_ro_w   = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
meta_ro_w  = (class_ro_t *)calloc(sizeof(class_ro_t), 1);
cls->data()->ro = cls_ro_w;
meta->data()->ro = meta_ro_w;

// 进行 allocate 分配，但没有注册
#define RW_CONSTRUCTING       (1<<26)
// ro 成员已经 copy 到 heap 空间上存储
#define RW_COPIED_RO          (1<<27)
// data 成员为可读写权限
#define RW_REALIZED           (1<<31)
// 表示该类已经记录，但尚未实现
#define RW_REALIZING          (1<<19)

// 进步信息数据操作
cls->data()->flags = RW_CONSTRUCTING | RW_COPIED_RO | RW_REALIZED | RW_REALIZING;
meta->data()->flags = RW_CONSTRUCTING | RW_COPIED_RO | RW_REALIZED | RW_REALIZING;
cls->data()->version = 0;
meta->data()->version = 7;

// 表示为 metaclass 类型
#define RO_META               (1<<0)

// cls 的 flags 属性不进行标记
cls_ro_w->flags = 0;
// meta_ro_w 的 flags 属性进行 metaclass 类型标记
meta_ro_w->flags = RO_META;
if (!superclass) {
	// 如果没有父类的话，则当前类也为 metaclass
   cls_ro_w->flags |= RO_ROOT;
   meta_ro_w->flags |= RO_ROOT;
}
if (superclass) {
	// 有无父类情况，传递 instanceStart
   cls_ro_w->instanceStart = superclass->unalignedInstanceSize();
   meta_ro_w->instanceStart = superclass->ISA()->unalignedInstanceSize();
   cls->setInstanceSize(cls_ro_w->instanceStart);
   meta->setInstanceSize(meta_ro_w->instanceStart);
} else {
   cls_ro_w->instanceStart = 0;
   meta_ro_w->instanceStart = (uint32_t)sizeof(objc_class);
   cls->setInstanceSize((uint32_t)sizeof(id));
   meta->setInstanceSize(meta_ro_w->instanceStart);
}

// 记录 Class 名
cls_ro_w->name = strdup(name);
meta_ro_w->name = strdup(name);

// 属性修饰符布局
// ivarLayout strong引用表
cls_ro_w->ivarLayout = &UnsetLayout;
// weakIvarLayout weak引用表
cls_ro_w->weakIvarLayout = &UnsetLayout;

// 通过获取到的 cls 指针，调用 isa 初始化命令
cls->initClassIsa(meta);
if (superclass) {
	// 如果拥有父类，更新 meta 的 isa 指向
   meta->initClassIsa(superclass->ISA()->ISA());
   // 更新 cls 父类信息
   cls->superclass = superclass;
   // meta 的父类指向父类的 isa
   meta->superclass = superclass->ISA();
   // 向父类中增加该类信息
   addSubclass(superclass, cls);
   // 向父类的 isa 中记录该信息
   addSubclass(superclass->ISA(), meta);
} else {
	// 为 meta 初始化 isa 信息
   meta->initClassIsa(meta);
   // 由于该类为 rootclass，无父类信息
   // 让其父类指向 Nil
   cls->superclass = Nil;
   // 令 meta 的父类指向 cls
   meta->superclass = cls;
   // 向 cls 中增加 meta 指针信息
   addSubclass(cls, meta);
}
```

在语法上需要注意这几个地方：
 
 * ivarLayout 和 weakIvarLayout：分别记录了哪些 ivar 是 strong 或是 weak，都未记录则为 __unsafe_unretained 的对象类型。
 * `strdup(const char *s)`：可以复制字符串。先回调用 malloc() 配置与参数 s 字符串的内容复制到该内存地址，然后把该地址返回。返回值是一个字符串指针，该指针指向复制后的新字符串地址。若返回 NULL 表示内存不足。

在上述代码中，会发现一个问题。当创建的 Class 没有父类的时候，其 meta 是指向 cls 自身的，而 meta 原本就是 cls 的子类，所以在这里，使得一个基类对象的 isa 指针形成自环指向自身。下图用 `NSObject` 举例（其指针下方有源码标注）：

![isa_obj_x](http://7xwh85.com1.z0.glb.clouddn.com/isa_obj_x.png)



而当创建 Class 拥有父类的时候，isa 和 superclass 都要指向父类，而对应的 meta 通过两次的 isa 查询找到根类 meta ，更新指向。用 `NSError` 来举例：

![isa_obj_x2](http://7xwh85.com1.z0.glb.clouddn.com/isa_metaclass.png)

其中要之一 meta 的 isa 操作 `meta->initClassIsa(superclass->ISA()->ISA());` ，这不是单纯的指向父类 meta 的操作，而是指向根类的 meta 。

*Talk is cheap!* ，用代码来实验一下：

```c
- (void)viewDidLoad {
    [super viewDidLoad];
    DGObject *desgard = [[DGObject alloc] init];
    
    Class cls = object_getClass(desgard);
    NSLog(@"%s\n", class_getName(cls)); // DGObject
    NSLog(@"%d\n", class_isMetaClass(cls)); // 0
    
    Class meta = object_getClass(cls);
    NSLog(@"%s\n", class_getName(meta)); // DGObject
    NSLog(@"%d\n", class_isMetaClass(cls)); // 0
    
    Class meta_meta = object_getClass(meta);
    NSLog(@"%s\n", class_getName(meta_meta)); // NSObject
    NSLog(@"%d\n", class_isMetaClass(meta_meta)); // 1
}
```


通过以上分析，我们知道了 metaclass 是一个 Class ，而这个 Class 是作为基础 Class 的所属类，用于构建**继承网图**，使得 runtime 访问相关联的 Class 更加的快捷方便。在 *[What is a meta-class in Objective-C?]()* 一文中，作者将其称作 **NSObject继承体系(NSObject hierarchy)** ，其根类所有的 Class 和相关 metaclass 都是联通的，并且在根类 NSObject 中的成员方法，对其体系中的所有 Class 和对应 metaclass 也是操作有效的。

metaclass 的存在，将对象化的实例、类组织成了一个连通图，进一步灵活了 ObjC 的动态特性。

至此，我们通过源码，系统了解了 isa 指针对于对象的信息记录，以及 metaclass 的结构和作用。后续博文将会探究 `retain` 和 `release` 方法，敬请期待。

> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。
