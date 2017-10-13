> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](https://desgard.com/objc_msgSend2/)


# 消息转发

该文是 *[objc_msgSend消息传递学习笔记 - 对象方法消息传递流程]()* 的基础上继续探究源码，请先阅读上文。

## 消息转发机制(message forwarding)

Objective-C 在调用对象方法的时候，是通过消息传递机制来查询且执行方法。如果想令该类能够理解并执行方法，必须以程序代码实现出对应方法。但是，在编译期间向类发送了无法解读的消息并不会报错，因为在 runtime 时期可以继续向类添加方法，所以编译器在编译时还无法确认类中是否已经实现了消息方法。

当对象接受到无法解读的消息后，就会启动**消息转发**机制，并且我们可以由此过程告诉对象应该如何处理位置消息。

本文的研究目标：当 Class 对象的 `.h` 文件中声明了成员方法，但是没有对其进行实现，来跟踪一下 runtime 的消息转发过程。于是创造一下实验场景：

> 同上一篇文章一样，定义一个自定义 Class `DGObject` ，并且声明改 Class 中拥有方法 `- (void)test_no_exist` ，而在 `.m` 文件中不给予实现。在 `main.m` 入口中直接调用该类对象的 `- (void)test_no_exist` 方法。

![](http://7xwh85.com1.z0.glb.clouddn.com/14722248187304.jpg)

## 动态方法解析

依旧在 lookUpImpOrForward 方法中下断点，并单步调试，观察代码走向。由于方法在方法列表中无法找到，所以立即进入 method resolve 过程。

```c
// 进入method resolve过程
if (resolver  &&  !triedResolver) {
	// 释放读入锁
   runtimeLock.unlockRead();
   // 调用_class_resolveMethod，解析没有实现的方法
   _class_resolveMethod(cls, sel, inst);
   // 进行二次尝试
   triedResolver = YES;
   goto retry;
}
```

`runtimeLock.unlockRead()` 是释放读入锁操作，这里是指缓存读入，即缓存机制不工作从而不会有缓存结果。随后进入 `_class_resolveMethod(cls, sel, inst)` 方法。

```c
void _class_resolveMethod(Class cls, SEL sel, id inst) {
	// 用 isa 查看是否指向元类 Meta Class
    if (! cls->isMetaClass()) {
        // try [cls resolveInstanceMethod:sel]
        _class_resolveInstanceMethod(cls, sel, inst);
    } 
    else {
        // try [nonMetaClass resolveClassMethod:sel]
        // and [cls resolveInstanceMethod:sel]
        _class_resolveClassMethod(cls, sel, inst);
        if (!lookUpImpOrNil(cls, sel, inst, 
                            NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
        {
            _class_resolveInstanceMethod(cls, sel, inst);
        }
    }
}
```

此方法是动态方法解析的入口，会间接地发送 `+resolveInstanceMethod` 或 `+resolveClassMethod` 消息。通过对 isa 指向的判断，从而分辨出如果是对象方法，则进入 `+resolveInstanceMethod` 方法，如果是类方法，则进入 `+resolveClassMethod` 方法。

而上述代码中的 `_class_resolveInstanceMethod` 方法，我们从源码中看到是如此定义的：

```c
static void _class_resolveInstanceMethod(Class cls, SEL sel, id inst) {
	// 首先查找是否有 resolveInstanceMethod 方法
    if (! lookUpImpOrNil(cls->ISA(), SEL_resolveInstanceMethod, cls, 
                         NO/*initialize*/, YES/*cache*/, NO/*resolver*/)) 
    {
        // Resolver not implemented.
        return;
    }
	// 构造布尔类型变量表达式，动态绑定函数
    BOOL (*msg)(Class, SEL, SEL) = (__typeof__(msg))objc_msgSend;
    // 获得是否重新传递消息标记
    bool resolved = msg(cls, SEL_resolveInstanceMethod, sel);

    // Cache the result (good or bad) so the resolver doesn't fire next time.
    // +resolveInstanceMethod adds to self a.k.a. cls
    // 调用 lookUpImpOrNil 并重新启动缓存，查看是否已经添加上了选择子对应的 IMP
    指针
    IMP imp = lookUpImpOrNil(cls, sel, inst, 
                             NO/*initialize*/, YES/*cache*/, NO/*resolver*/);
	// 对查询到的 IMP 进行 log 输出
    if (resolved  &&  PrintResolving) {
        if (imp) {
            _objc_inform("RESOLVE: method %c[%s %s] "
                         "dynamically resolved to %p", 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel), imp);
        }
        else {
            // Method resolver didn't add anything?
            _objc_inform("RESOLVE: +[%s resolveInstanceMethod:%s] returned YES"
                         ", but no new implementation of %c[%s %s] was found",
                         cls->nameForLogging(), sel_getName(sel), 
                         cls->isMetaClass() ? '+' : '-', 
                         cls->nameForLogging(), sel_getName(sel));
        }
    }
}
```

通过 `_class_resolveInstanceMethod` 可以了解到，这只是通过 `+resolveInstanceMethod` 来查询是否开发者已经在运行时将其动态插入类中的实现函数。并且重新触发 `objc_msgSend` 方法。这里有一个 C 的语法值得我们去延伸学习一下，就是关于关键字 `__typeof__` 的。`__typeof__(var)` 是 GCC 对 C 的一个扩展保留字([官方文档](https://gcc.gnu.org/onlinedocs/gcc/Typeof.html))，这里是用来描述一个指针的类型。

我们发现，最终都会返回到 `objc_msgSend` 中。反观一下上一篇文章写的 `objc_msgSend` 函数，是通过汇编语言实现的。在 *[Let's build objc_msgsend](https://www.mikeash.com/pyblog/friday-qa-2012-11-16-lets-build-objc_msgsend.html)* 这篇资料中，记录了一个关于 `objc_msgSend` 的伪代码。

```c
id objc_msgSend(id self, SEL _cmd, ...) {
	Class c = object_getClass(self);
	IMP imp = cache_lookup(c, _cmd);
	if(!imp)
		imp = class_getMethodImplementation(c, _cmd);
	return imp(self, _cmd, ...);
}
``` 

在缓存中无法直接击中 IMP 时，会调用 `class_getMethodImplementation` 方法。在 runtime 中，查看一下 `class_getMethodImplementation` 方法。

```c
IMP class_getMethodImplementation(Class cls, SEL sel)
{
    IMP imp;

    if (!cls  ||  !sel) return nil;
	// 上一篇文章的搜索入口
    imp = lookUpImpOrNil(cls, sel, nil, 
                         YES/*initialize*/, YES/*cache*/, YES/*resolver*/);

    // Translate forwarding function to C-callable external version
    if (!imp) {
        return _objc_msgForward;
    }

    return imp;
}
```

在上一篇文中，详细介绍过了 `lookUpImpOrNil` 函数成功搜索的流程。而本例中与前相反，我们我发现该函数返回了一个 `_objc_msgForward` 的 IMP。此时，我们击中的函数是 `_objc_msgForward` 这个 IMP ，于是消息转发机制进入了**备援接收**流程。

## Forwarding 备援接收

`_objc_msgForward` 居然可以返回，说同 IMP 一样是一个指针。在 `objc-msg-x86_64.s` 中发现了其汇编实现。

```c
ENTRY	__objc_msgForward
// Non-stret version
// 调用 __objc_forward_handler
movq	__objc_forward_handler(%rip), %r11
jmp	*%r11

END_ENTRY	__objc_msgForward
```

发现在接收到 `_objc_msgForward` 指针后，会立即进入 `__objc_forward_handler` 方法。其源码在 `objc-runtime.mm` 中。

```c
#if !__OBJC2__

// Default forward handler (nil) goes to forward:: dispatch.
void *_objc_forward_handler = nil;
void *_objc_forward_stret_handler = nil;

#else

// Default forward handler halts the process.
__attribute__((noreturn)) void 
objc_defaultForwardHandler(id self, SEL sel) {
    _objc_fatal("%c[%s %s]: unrecognized selector sent to instance %p "
                "(no message forward handler is installed)", 
                class_isMetaClass(object_getClass(self)) ? '+' : '-', 
                object_getClassName(self), sel_getName(sel), self);
}
void *_objc_forward_handler = (void*)objc_defaultForwardHandler;
```

在 ObjC 2.0 以前，`_objc_forward_handler` 是 nil ，而在最新的 runtime 中，其实现由 `objc_defaultForwardHandler` 完成。其源码仅仅是在 log 中记录一些相关信息，这也是 handler 的主要功能。

而抛开 runtime ，看见了关键字 `__attribute__((noreturn))` 。这里简单介绍一下 GCC 中的又一扩展 **__attribute__机制** 。它用于与编译器直接交互，这是一个编译器指令(Compiler Directive)，用来在函数或数据声明中设置属性，从而进一步进行优化(继续了解可以阅读 *[NShipster \__attribute__](http://nshipster.com/__attribute__/)*)。而这里的 `__attribute__((noreturn))` 是告诉编译器此函数不会返回给调用者，以便编译器在优化时去掉不必要的函数返回代码。

Handler 的全部工作是记录日志、触发 crash 机制。如果开发者想实现细节转发，则需要重写 `_objc_forward_handler` 中的实现。这时引入 `objc_setForwardHandler` 方法：

```c
void objc_setForwardHandler(void *fwd, void *fwd_stret) {
    _objc_forward_handler = fwd;
#if SUPPORT_STRET
    _objc_forward_stret_handler = fwd_stret;
#endif
}
```

这是一个十分简单的动态绑定过程，让方法指针指向传入参数指针得以实现。

## Core Foundation 衔接

引入 `objc_setForwardHandler` 方法后，会有一个疑问：如何调用它？先来看一段异常信息：

```bash
2016-08-27 08:26:08.264 debug-objc[7013:29381250] -[DGObject test_no_exist]: unrecognized selector sent to instance 0x101200310
2016-08-27 10:09:16.495 debug-objc[7013:29381250] *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[DGObject test_no_exist]: unrecognized selector sent to instance 0x101200310'
*** First throw call stack:
(
	0   CoreFoundation                      0x00007fff842c64f2 __exceptionPreprocess + 178
	1   libobjc.A.dylib                     0x000000010002989f objc_exception_throw + 47
	2   CoreFoundation                      0x00007fff843301ad -[NSObject(NSObject) doesNotRecognizeSelector:] + 205
	3   CoreFoundation                      0x00007fff84236571 ___forwarding___ + 1009
	4   CoreFoundation                      0x00007fff842360f8 _CF_forwarding_prep_0 + 120
	5   debug-objc                          0x0000000100000e9e main + 94
	6   libdyld.dylib                       0x00007fff852a95ad start + 1
	7   ???                                 0x0000000000000001 0x0 + 1
)
libc++abi.dylib: terminating with uncaught exception of type NSException
```

这个日志场景都接触过。从调用栈上，发现了最终是通过 Core Foundation 抛出异常。在 Core Foundation 的 [CFRuntime.c](https://github.com/opensource-apple/CF/blob/master/CFRuntime.c) 无法找到 `objc_setForwardHandler` 方法的调用入口。综合参看 *[Objective-C 消息发送与转发机制原理](http://yulingtianxia.com/blog/2016/06/15/Objective-C-Message-Sending-and-Forwarding/)* 和 *[Hmmm, What's that Selector?](http://arigrant.com/blog/2013/12/13/a-selector-left-unhandled)* 两篇文章，我们发现了在 [CFRuntime.c](https://github.com/opensource-apple/CF/blob/master/CFRuntime.c) 的 `__CFInitialize()` 方法中，实际上是调用了 `objc_setForwardHandler` ，这段代码被苹果公司隐藏。

在上述调用栈中，发现了在 Core Foundation 中会调用 `___forwarding___` 。根据资料也可以了解到，在 `objc_setForwardHandler` 时会传入 `__CF_forwarding_prep_0` 和 `___forwarding_prep_1___` 两个参数，而这两个指针都会调用 `____forwarding___` 。这个函数中，也交代了消息转发的逻辑。在 *[Hmmm, What's that Selector?](http://arigrant.com/blog/2013/12/13/a-selector-left-unhandled)* 文章中，复原了 `____forwarding___` 的实现。

```c
// 两个参数：前者为被转发消息的栈指针 IMP ，后者为是否返回结构体
int __forwarding__(void *frameStackPointer, int isStret) {
  id receiver = *(id *)frameStackPointer;
  SEL sel = *(SEL *)(frameStackPointer + 8);
  const char *selName = sel_getName(sel);
  Class receiverClass = object_getClass(receiver);

  // 调用 forwardingTargetForSelector:
  // 进入 备援接收 主要步骤
  if (class_respondsToSelector(receiverClass, @selector(forwardingTargetForSelector:))) {
	// 获得方法签名
    id forwardingTarget = [receiver forwardingTargetForSelector:sel];
    // 判断返回类型是否正确
    if (forwardingTarget && forwarding != receiver) {
	    // 判断类型，是否返回值为结构体，选用不同的转发方法
    	if (isStret == 1) {
    		int ret;
    		objc_msgSend_stret(&ret,forwardingTarget, sel, ...);
    		return ret;
    	}
      return objc_msgSend(forwardingTarget, sel, ...);
    }
  }

  // 僵尸对象
  const char *className = class_getName(receiverClass);
  const char *zombiePrefix = "_NSZombie_";
  size_t prefixLen = strlen(zombiePrefix); // 0xa
  if (strncmp(className, zombiePrefix, prefixLen) == 0) {
    CFLog(kCFLogLevelError,
          @"*** -[%s %s]: message sent to deallocated instance %p",
          className + prefixLen,
          selName,
          receiver);
    <breakpoint-interrupt>
  }

  // 调用 methodSignatureForSelector 获取方法签名后再调用 forwardInvocation
  // 进入消息转发系统
  if (class_respondsToSelector(receiverClass, @selector(methodSignatureForSelector:))) {
    NSMethodSignature *methodSignature = [receiver methodSignatureForSelector:sel];
    // 判断返回类型是否正确
    if (methodSignature) {
      BOOL signatureIsStret = [methodSignature _frameDescriptor]->returnArgInfo.flags.isStruct;
      if (signatureIsStret != isStret) {
        CFLog(kCFLogLevelWarning ,
              @"*** NSForwarding: warning: method signature and compiler disagree on struct-return-edness of '%s'.  Signature thinks it does%s return a struct, and compiler thinks it does%s.",
              selName,
              signatureIsStret ? "" : not,
              isStret ? "" : not);
      }
      if (class_respondsToSelector(receiverClass, @selector(forwardInvocation:))) {
	    // 传入消息的全部细节信息
        NSInvocation *invocation = [NSInvocation _invocationWithMethodSignature:methodSignature frame:frameStackPointer];

        [receiver forwardInvocation:invocation];

        void *returnValue = NULL;
        [invocation getReturnValue:&value];
        return returnValue;
      } else {
        CFLog(kCFLogLevelWarning ,
              @"*** NSForwarding: warning: object %p of class '%s' does not implement forwardInvocation: -- dropping message",
              receiver,
              className);
        return 0;
      }
    }
  }

  SEL *registeredSel = sel_getUid(selName);

  // selector 是否已经在 Runtime 注册过
  if (sel != registeredSel) {
    CFLog(kCFLogLevelWarning ,
          @"*** NSForwarding: warning: selector (%p) for message '%s' does not match selector known to Objective C runtime (%p)-- abort",
          sel,
          selName,
          registeredSel);
  } 
  // doesNotRecognizeSelector，主动抛出异常
  // 也就是前文我们看到的
  // 表明选择子未能得到处理
  else if (class_respondsToSelector(receiverClass,@selector(doesNotRecognizeSelector:))) {
    [receiver doesNotRecognizeSelector:sel];
  } 
  else {
    CFLog(kCFLogLevelWarning ,
          @"*** NSForwarding: warning: object %p of class '%s' does not implement doesNotRecognizeSelector: -- abort",
          receiver,
          className);
  }

  // The point of no return.
  kill(getpid(), 9);
}
```

## Message-Dispatch System 消息派发系统

在大概了解过 Message-Dispatch System 的源码后，来简单的说明一下。由于在前两步中，我们无法找到那条消息的实现。则创建一个 NSInvocation 对象，并将消息全部属性记录下来。 NSInvocation 对象包括了选择子、target 以及其他参数。

随后，调用 `forwardInvocation:(NSInvocation *)invocation` 方法，其中的实现仅仅是改变了 target 指向，使消息保证能够调用。倘若发现本类无法处理，则继续想父类进行查找。直至 NSObject ，如果找到根类仍旧无法找到，则会调用 `doesNotRecognizeSelector:` ，以抛出异常。此异常表明选择子最终未能得到处理。

而对于 `doesNotRecognizeSelector:` 内部是如何实现，如何捕获异常。或者说 override 改方法后做自定义处理，等笔者实践后继续记录学习笔记。

## 对于消息转发的总结梳理

在 Core Foundation 的消息派发流程中，由于源码被隐藏，所以笔者无法亲自测试代码。倘若以后学习了逆向，可以再去探讨一下这里面发生的过程。

对于这篇文章记录的消息转发流程，大致如下图所示：


![Desktop](http://7xwh85.com1.z0.glb.clouddn.com/Desktop.png)


以上是对于 objc_msgSend 消息转发的源码学习笔记，请多指正。

---

## 参考资料

[Let's Build objc_msgSend](https://www.mikeash.com/pyblog/friday-qa-2012-11-16-lets-build-objc_msgsend.html)

[Hmmm, What's that Selector?](http://arigrant.com/blog/2013/12/13/a-selector-left-unhandled)

[NShipster \__attribute__](http://nshipster.com/__attribute__/)

[Objective-C 消息发送与转发机制原理](http://yulingtianxia.com/blog/2016/06/15/Objective-C-Message-Sending-and-Forwarding/)

> 若想查看更多的iOS Source Probe文章，收录在这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。



