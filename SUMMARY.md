# Summary

* [简介](README.md)

## Part 1 - iOS Runtime 源码解析
* objc/runtime.h 708
  * [浅谈Associated Objects](Objective-C/Runtime/浅谈Associated Objects.md)
  * [对象方法消息传递流程](Objective-C/Runtime/objc_msgSend消息传递学习笔记 - 对象方法消息传递流程.md)
  * [消息转发过程分析](Objective-C/Runtime/objc_msgSend消息传递学习笔记 - 消息转发.md)
  * [用 isa 承载对象的类信息](Objective-C/Runtime/用 isa 承载对象的类信息.md)
  * [weak 弱引用的实现方式](Objective-C/Runtime/weak 弱引用的实现方式.md)
  * [load 方法全程跟踪](Objective-C/Runtime/load 方法全程跟踪.md)
  * [浅谈 block - clang 改写后的 block 结构](Objective-C/Runtime/浅谈 block（1） - clang 改写后的 block 结构.md)
  * [浅谈 block - 截获变量方式](Objective-C/Runtime/浅谈 block（2） - 截获变量方式.md)

## Part 2 - macOS & iOS 系统源码分析 
* cctools/include/mach-o 895
  * [Mach-O 文件格式探索](C/mach-o/Mach-O 文件格式探索.md)

## Part 3 - Foundation 框架源码分析
* Foundation
  * [从经典问题来看 Copy 方法](Objective-C/Foundation/从经典问题来看 Copy 方法.md)
  * [CFArray 的历史渊源及实现原理](Objective-C/Foundation/CFArray 的历史渊源及实现原理.md)
  * [Run Loop 记录与源码注释(作者Kylin)](Objective-C/Foundation/Run Loop 记录与源码注释.md)

## Part 4 - UIKit 源码分析
* UIKit
  * [复用的精妙 - UITableView 复用技术原理分析](Objective-C/Foundation/复用的精妙 - UITableView 复用技术原理分析.md)

## Part 5 - SDWebImage 源码分析
* SDWebImage v3.8.1
  * [SDWebImage Source Probe: WebCache](Objective-C/SDWebImage/SDWebImage Source Probe - WebCache.md)
  * [SDWebImage Source Probe: Manager](Objective-C/SDWebImage/SDWebImage Source Probe - Manager.md)
  * [SDWebImage Source Probe: Downloader](Objective-C/SDWebImage/SDWebImage Source Probe - Downloader.md)
  * [SDWebImage Source Probe: Operation](Objective-C/SDWebImage/SDWebImage Source Probe - Operation.md)

## Part 6 - Swift 源码分析
* Swift v4.0
  * [Swift Probe - Optional](Swift/Swift Probe - Optional.md)

## Part 7 - Shadowsocks 源码分析
* Shadowsocks v4.0
  * [Shadowsocks Probe I - Socks5 与 EventLoop 事件分发](Python/Shadowsocks/Shadowsocks Probe I - Socks5 与 EventLoop 事件分发.md)
