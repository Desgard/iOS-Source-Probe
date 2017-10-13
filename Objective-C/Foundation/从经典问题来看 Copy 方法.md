> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/2016/08/11/copy/)

# 从经典问题来看 Copy 方法

> 本文中所用的 Test 可以从[这里](https://github.com/Desgard/iOS-Source-Probe/tree/master/project/TestCopy)获取。

在初学 iOS 的时候，可能会被灌输这么一个常识，**切记 NSString 的 property 的修饰变量要写作 copy ，而不是 strong**，那么这是为什么？

> 经典面试题：为什么 NSString 类型成员变量的修饰属性用 copy 而不是 strong (或 retain ) ？

## review Copy Operation

### Test 1

先来模拟一个程序设计错误的场景。有一个叫做 Person 的 Class，其中它拥有一个 NSString 类型的 s_name 属性（代表 name 是 strong），我们想给一个对象的 s_name 赋值，并且之前的赋值变量还想重复使用到其他场景。所以，我们在引入这个 Class 的 ViewController 进行如下操作：

```c
- (void)test1 {
    self.one = [[Person alloc] init];
    NSMutableString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.s_name = name;
    
    NSLog(@"%@", self.one.s_name);
    
    [name appendString:@" Source Probe"];
    
    NSLog(@"%@", self.one.s_name);
}
```

如果在 Person 这个 Class 中，我们的 s_name 的修饰属性是 **strong** 的话，会看到如下输出结果。

```c
2016-08-12 05:51:21.262 TestCopy[64714:20449045] iOS
2016-08-12 05:51:21.262 TestCopy[64714:20449045] iOS Source Probe
```

可是，我们操作的仅仅是对 s_name 那个变量，为什么连属性当中的 s_name 也会被改变？对这段代码稍做修改，重新测试。

### Test 2

```c
- (void)test2 {
    self.one = [[Person alloc] init];
    NSString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.s_name = name;
    
    NSLog(@"%@", self.one.s_name);
    
    name = @"iOS Source Probe";
    
    NSLog(@"%@", self.one.s_name);
}
```

这一次我们看到了输出结果是正常的：

```c
2016-08-12 05:56:57.162 TestCopy[64842:20459179] iOS
2016-08-12 05:56:57.162 TestCopy[64842:20459179] iOS
```

### Test 3

再来做第三个实验，我们换用 copy 类型的成员 c_name，来替换实验1中的 s_name ，查看一下输出结果。

最后发现输出结果依旧是我们所需要的。

```c
- (void)test3 {
    self.one = [[Person alloc] init];
    NSMutableString *name = [NSMutableString stringWithFormat:@"iOS"];
    self.one.c_name = name;
    
    NSLog(@"%@", self.one.c_name);
    
    [name appendString:@" Source Probe"];
    
    NSLog(@"%@", self.one.c_name);
}
```

```c
2016-08-12 06:03:40.226 TestCopy[64922:20479646] iOS
2016-08-12 06:03:40.227 TestCopy[64922:20479646] iOS
```

做过如上三个实验，或许你会知道对 property 使用 copy 修饰属性的原因了。也就是在一个特定场景下：**当我们通过一个 NSMutableString 对 NSString 变量进行赋值，如果 NSString 的 property 是 strong 类型的时候，就会随着 NSMutableString 类型的变量一起变化**。

这个猜测是正确的。在 [stackoverflow](http://stackoverflow.com/questions/11249656/should-an-nsstring-property-under-arc-be-strong-or-copy) 上也对这个场景进行单独的描述。可是原因是什么？继续做下面的实验：

### Test 4

```c
- (void)test4 {
    NSMutableString *str = [NSMutableString stringWithFormat:@"iOS"];
    
    NSLog(@"%p", str);
    
    NSString *str_a = str;
    
    NSLog(@"%p", str_a);
    
    NSString *str_b = [str copy];
    
    NSLog(@"%p", str_b);
}
```

输出地址后，我们发现以下结果：

```c
2016-08-12 06:15:45.169 TestCopy[65230:20515110] 0x7faf28429e70
2016-08-12 06:15:45.170 TestCopy[65230:20515110] 0x7faf28429e70
2016-08-12 06:15:45.170 TestCopy[65230:20515110] 0xa00000000534f693
```

发现当令 NSString 对象指针指向一个 NSMutableString 类型变量通过 copy 方法返回的对象，则会对其进行**深复制**。这也就是我们一直所说的在一个 Class 的成员是 NSString 类型的时候，修饰属性应该使用 copy ，其实就是在使用 mutable 对象进行赋值的时候，防止 mutable 对象的改变从而影响成员变量。从 MRC 的角度来看待修饰属性，若一个属性的关键字为 retain （可等同于 strong ），则在进行指针的指向修改时，如上面的`self.one.name = str`，其实是执行了`self.one.name = [str retain]`，而 copy 类型的属性则会执行`self.one.name = [str copy]`。

而在 Test 2 中，我们的实验是将一个 NSString 对象指向另外一个 NSString 对象，那么如果前者是 copy 的成员，还会进行**深复制**吗？进行下面的 Test 5，我们令 c_name 的修饰变量为 copy。

### Test 5

```c
- (void)test5 {
    self.one = [[Person alloc] init];
    NSString *name = [NSMutableString stringWithFormat:@"iOS"];
    
    self.one.c_name = name;
    NSLog(@"%@", self.one.c_name);
    
    name = @"iOS Source Probe";
    NSLog(@"%@", self.one.c_name);
    
    NSString *str = [NSString stringWithFormat:@"iOS"];
    NSLog(@"%p", str);
    
    NSString *str_a = str;
    NSLog(@"%p", str_a);
    
    NSString *str_b = [str copy];
    NSLog(@"%p", str_b);
}
```

发现结果符合猜测：

```c
2016-08-12 08:09:28.125 TestCopy[66402:20671038] iOS
2016-08-12 08:09:28.126 TestCopy[66402:20671038] iOS
2016-08-12 08:09:28.126 TestCopy[66402:20671038] 0xa00000000534f693
2016-08-12 08:09:28.126 TestCopy[66402:20671038] 0xa00000000534f693
2016-08-12 08:09:28.126 TestCopy[66402:20671038] 0xa00000000534f693
```

从一个 NSString 进行 copy 后赋值，copy 方法仍旧是**浅拷贝**。这个效果就等同于`str_b = [str retain]`，在 ARC 中即 `str_b = str`。

那么，如何在这种情况下，让`str_b`指向一个`str`的深拷贝呢，答案就是`str_b = [str mutableCopy]`。这也就是 copy 和 mutableCopy 的区别。

## copy & mutableCopy

下面我们开始对 copy 和 mutableCopy 原理进行分析。以下也是我的源码学习笔记。

在[opensource.apple.com的git仓库中](git@github.com:RetVal/objc-runtime.git)的Runtime源码中有`NSObject.mm`这个文件，其中有如下方法是关于 copy 的：

```c
- (id)copy {
    return [(id)self copyWithZone:nil];
}

- (id)mutableCopy {
    return [(id)self mutableCopyWithZone:nil];
}
```

发现`copy`和`mutableCopy`两个方法只是简单调用了`copyWithZone:`和`mutableCopyWithZone:`两个方法。所以有了以下猜想：对于 NSString 和 NSMutableString，Foundation 框架已经为我们实现了 copyWithZone 和 mutableCopyWithZone 的源码。我在[searchcode.com](https://searchcode.com)找到了 Hack 版的 NSString 和 NSMutableString 的 Source Code。

在[NSString.m](https://searchcode.com/file/12532490/libFoundation/Foundation/NSString.m)中，看到了以下关于 copy 的方法。

```c
- (id)copyWithZone:(NSZone *)zone {
    if (NSStringClass == Nil)
        NSStringClass = [NSString class];
    return RETAIN(self);
}

- (id)mutableCopyWithZone:(NSZone*)zone {
    return [[NSMutableString allocWithZone:zone] initWithString:self];
}
```

而在 [NSMutableString.m](https://searchcode.com/file/68838008/jni%20w:%20itoa%20runtime%20and%20allocator/Foundation/NSMutableString.m) 中只发现了`copyWithZone:`和`copy:`方法，并且它调用了父类的**全能初始化方法（designated initializer）**，所以构造出来的对象是由 NSString 持有的：

```c
-(id)copy {
    return [[NSString alloc] initWithString:self];
}

-(id)copyWithZone:(NSZone*)zone {
    return [[NSString allocWithZone:zone] initWithString:self];
}
```

也就是说， NSMutableString 进行 copy 的对象从源码上看也会变成深复制方法。我们做下试验。

### Test 6

```c
- (void)test6 {
    NSMutableString *str = [NSMutableString stringWithFormat:@"iOS"];
    NSLog(@"%p", str);
    NSMutableString *str2 = [str copy];
    NSLog(@"%p", str2);
}
```

```c
2016-08-12 15:12:12.845 TestCopy[73658:21549553] 0x7f96f8410e10
2016-08-12 15:12:12.846 TestCopy[73658:21549553] 0xa00000000534f693
```

输出结果如我们所预料的，同样是 NSMutableString 之间的指针传递，即使类型相同，使用了该类型下的 copy 方法，也会变成深复制，因为返回的对象如源码所示，调用了 NSString 的全能初始化方法，并且由一个新的 NSString 持有。那么在 NSMutableString 中使用`mutableCopy`，可以做到单纯的 retain 操作吗。答案也是否定的，同样是源码中写道，在源码中并没有重写`mutableCopy`方法，也没有实现`mutableCopyWithZone:`方法，所以会调用父类的`mutableCopyWithZone`。而在父类中 `mutableCopyWithZone:`方法中调用了 NSMutableString 的全局初始化方法，所以依旧是深复制。

以上原则试用于大多数 Foundation 框架中的常用类，如 NSArray 、 NSDictionary 等等。

## 关于自定义 Class 的 Copy 方法

对于以上所有试验，我们可以总结一种关系：


![14709874979001.jpg](http://upload-images.jianshu.io/upload_images/208988-5769dfa1eed5e9fd.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



由此，我们可以总结一下。其实 Copy 对应的也就是类似于 **immutableCopy** 这种感觉，因为通过 copy 出的对象总是不可变的。所以对于一个 Class 中的 mutableCopy 和 copy 的方法命名而言，其实是否有 mutable ，是**针对于返回值而言的**。在 Foundation Framework 中，把拷贝方法称为 copy 而非 immutableCopy 的原因在于，NSCopying 这个基础协议不仅设计给那些具有可变和不可变版本的类来用，而且还要供其他一些没有“可变”和“不可变”之分的类来用。

所以在实现自定义 Class 的 Copy 方法适合，我们需要确定一个问题，应该执行深复制还是浅复制。然后在去实现对应的 `copyWithZone:` 和 `mutableCopyWithZone:` 两个方法。这里我不再多论，可以查看 *Effective Objective-C 2.0 52 Specific Ways to Improve Your iOS and OS X Programes* 的 *Tips 22* 。

## 对于很多博文的一些疑问

在很多关于讨论自定义 Class 中的 Copy 方法，都会强调一句：**我们一定要遵循 NSCopying 或 NSMutableCopying 这两个协议**，并且在实例代码中也显式写出了自定义的 Class 是遵循这两个协议的，如下：

```c
@interface XXObject: NSObject<NSCopying, NSMutableCopying>

@end
```

但是如果我们不显式的写出，我们发现不但没有 crash ，而且结果也是完全一样的。而在 *[Objective-C copy那些事儿](http://zhangbuhuai.com/copy-in-objective-c/)* 此文中，作者写道：

> 正确的做法是让自定义类遵循NSCopying协议（**NSObject并未遵循该协议**）

我的猜想是，某次苹果所用的 Foundation 框架升级，使得 NSObject 开始遵循 NSCopying 方法，但是没有去实现（这就好比 c++ 中的 virtual 虚函数）。这里有待考证，如果有朋友知道，欢迎补充这一部分知识，请大家多多指教。

---
多谢4楼 @[hpppp](http://www.jianshu.com/users/bfa2516c1fa2) 的解释：

> [hpppp](http://www.jianshu.com/users/bfa2516c1fa2): 显式写明遵循该协议只是说运行时如果调用conformToProtocol的话，返回会是true，否则返回false，等可能还有一些其它的运行时信息，就像c#／java的反射一样。 而这里没有显式声明，但你依然实现了该协议中的方法，这时候运行时调用copy时，会转成调用copyWithZone，此时该方法存在，那么调用就不会抛出异常。

---

> 以上是个人在学习 Foundation 框架的一些源码分析和猜想，如果想了解更多的 *iOS Source Probe* 系列文章，可以访问 github 仓库 [iOS-Source-Probe](https://github.com/Desgard/iOS-Source-Probe)。


