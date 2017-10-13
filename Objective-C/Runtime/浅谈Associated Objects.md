> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](http://www.desgard.com/2016/07/30/AssociatedObjectsIntroduction/)

# 浅谈Associated Objects

俗话说：“金无足赤，人无完人。”对于每一个Class也是这样，尽管我们说这个Class的代码规范、逻辑清晰合理等等，但是总会有它的短板，或者随着需求演进而无法订制实现功能。于是在Objective-C 2.0中引入了**category**这个特性，用以动态地为已有类添加新行为。面向对象的设计用来描述事物的组成往往是使用Class中的属性成员，这也就**局限了方法的广度**（在官方文档称之为**[An otherwise notable shortcoming for Objective-C](https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/CustomizingExistingClasses/CustomizingExistingClasses.html)**，译为：*Objc的一个显著缺陷*）。所以在Runtime中引入了**Associated Objects**来弥补这一缺陷。

另外，请带着以下疑问来阅读此文：

* Associated Objects 使用场景。
* Associated Objects 五种`objc_AssociationPolicy`有什么区别。
* Associated Objects 的存储结构。

## Associated Objects Introduction

Associated Objects是Objective-C 2.0中Runtime的特性之一。最早开始使用是在*OS X Snow Leopard*和*iOS 4*中。在`<objc/runtime.h>`中定义的三个方法，也是我们深入探究Associated Objects的突破口：

* objc_setAssociatedObject
* objc_getAssociatedObject
* objc_removeAssociatedObjects

> void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)


* `object`：传入关联对象的所属对象，也就是增加成员的实例对象，一般来说传入self。
* `key`：一个唯一标记。在官方文档中推荐使用`static char`，当然更推荐是指针。为了便捷，一般使用`selector`，这样在后面getter中，我们就可以利用`_cmd`来方便的取出`selector`。
* `value`：传入关联对象。
* `policy`：`objc_AssociationPolicy`是一个ObjC枚举类型，也代表关联策略。

> void objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)

 > void objc_removeAssociatedObjects(id object)

从参数类型参数类型上，我们可以轻易的得出getter和remove方法传入参数的含义。要注意的是，**objc_removeAssociatedObjects这个方法会移除一个对象的所有关联对象。**其实，该方法我们一般是用不到的，移除所有关联意味着将类恢复成**无任何关联的原始状态**，这不是我们希望的。所以一般的做法是通过`objc_setAssociatedObject`来传入`nil`，从而移除某个已有的关联对象。

我们用[Associated Objects](http://nshipster.com/associated-objects/)这篇文中的例子来举例：

```c
// NSObject+AssociatedObject.h

@interface NSObject (AssociatedObject)
@property (nonatomic, strong) id associatedObject;
@end
```

```c
// NSObject+AssociatedObject.m

@implementation NSObject (AssociatedObject)
@dynamic associatedObject;

- (void)setAssociatedObject:(id)object {
     objc_setAssociatedObject(self, @selector(associatedObject), object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)associatedObject {
    return objc_getAssociatedObject(self, @selector(associatedObject));
}
```

这时我们已经发现`associatedObject`这个属性已经添加至`NSObject`的实例中了。并且我们可以通过category指定的getter和setter方法对这个属性进行存取操作。（注：这里使用`@dynamic`关键字是为了告知编译器：**在编译期不要自动创建实现属性所用的存取方法**。因为对于Associated Objects我们**必须手动添加**。当然，不写这个关键字，使用同名方法进行override也是可以达到相同效果的。但从编码规范和优化效率来讲，显式声明是最好的。）


![1.jpg](http://upload-images.jianshu.io/upload_images/208988-10a9d08b532258d3.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


## AssociationPolicy

通过上面的例子，我们注意到了`OBJC_ASSOCIATION_RETAIN_NONATOMIC`这个参数，它的枚举类型各个元素的含义如下：

Behavior | @property Equivalent | Description
--------- | ------------- | --------
OBJC_ASSOCIATION_ASSIGN | @property (assign) 或 @property (unsafe_unretained) | 指定一个关联对象的弱引用。
OBJC_ASSOCIATION_RETAIN_NONATOMIC | @property (nonatomic, strong) | 指定一个关联对象的强引用，不能被原子化使用。
OBJC_ASSOCIATION_COPY_NONATOMIC | @property (nonatomic, copy) | 指定一个关联对象的copy引用，不能被原子化使用。
OBJC_ASSOCIATION_RETAIN | @property (atomic, strong) | 指定一个关联对象的强引用，能被原子化使用。
OBJC_ASSOCIATION_COPY | @property (atomic, copy) | 指定一个关联对象的copy引用，能被原子化使用。
OBJC_ASSOCIATION_GETTER_AUTORELEASE | | 自动释放类型 

OBJC_ASSOCIATION_ASSIGN类型的关联对象和`weak`有一定差别，而更加接近于`unsafe_unretained`，即当目标对象遭到摧毁时，属性值不会自动清空。（翻译自[Associated Objects](http://nshipster.com/associated-objects/)）

## Usage Sample

同样是[Associated Objects](http://nshipster.com/associated-objects/)文中，总结了三个关于Associated Objects用法：

* **为Class添加私有成员**：例如在AFNetworking中，[在UIImageView里添加了**imageRequestOperation**对象](https://github.com/AFNetworking/AFNetworking/blob/2.1.0/UIKit%2BAFNetworking/UIImageView%2BAFNetworking.m#L57-L63)，从而保证了异步加载图片。
* **为Class添加共有成员**：例如在FDTemplateLayoutCell中，使用Associated Objects来缓存每个cell的高度（[代码片段1](https://github.com/mconintet/UITableView-FDTemplateLayoutCell/blob/master/Classes/UITableView+FDIndexPathHeightCache.m#L124)、[代码片段2](https://github.com/mconintet/UITableView-FDTemplateLayoutCell/blob/master/Classes/UITableView+FDKeyedHeightCache.m#L81)）。通过分配不同的key，在复用cell的时候即时取出，增加效率。
* **创建KVO对象**：建议使用category来创建关联对象作为观察者。可以参考[*Objective-C Associated Objects*](http://kingscocoa.com/tutorials/associated-objects/)这篇文的例子。


## Analysis Source Code

在[*Objective-C Associated Objects 的实现原理*](http://blog.leichunfeng.com/blog/2015/06/26/objective-c-associated-objects-implementation-principle/)这篇文中，作者有一个[例子](https://github.com/leichunfeng/AssociatedObjects)，作者分析了在Associated Objects中弱引用的区别。其代码片段如下：

```c
#import "ViewController.h"
#import "ViewController+AssociatedObjects.h"

__weak NSString *string_weak_assign = nil;
__weak NSString *string_weak_retain = nil;
__weak NSString *string_weak_copy   = nil;

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 通过[NSString stringWithFormat:]来持有一个字符串对象
    self.associatedObject_assign = [NSString stringWithFormat:@"associatedObject_assign"];
    self.associatedObject_retain = [NSString stringWithFormat:@"associatedObject_retain"];
    self.associatedObject_copy   = [NSString stringWithFormat:@"associatedObject_copy"];
	
	// 强调指向各个属性的指针均为弱类型指针
	// 以保证weak、assign类型属性会被释放
    string_weak_assign = self.associatedObject_assign;
    string_weak_retain = self.associatedObject_retain;
    string_weak_copy   = self.associatedObject_copy;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    NSLog(@"self.associatedObject_assign: %@", self.associatedObject_assign); // Will Crash
    NSLog(@"self.associatedObject_retain: %@", self.associatedObject_retain);
    NSLog(@"self.associatedObject_copy:   %@", self.associatedObject_copy);
}

@end
```

在测试时候，我们发现有些情况下不至于导致crash。我猜想可能是因为`[NSString stringWithFormat:]`方法的持有字符串可能会被编译器优化成*compile-time constant*。你可以尝试着做如下修改：

```c
self.associatedObject_assign = @"associatedObject_assign";
self.associatedObject_retain = @"associatedObject_retain";
self.associatedObject_copy   = @"associatedObject_copy";
```

你会发现全部正常输出。因为所有字符串都变成了编译期常量而存储起来。所以探究方法，应该是讲类型更改成NSObject进行试验。

### Setter Source Code

我们一直有个疑问，就是关联对象是如何存储的。下面我们看下*Runtime*的源码。

以下源码来自于[opensource.apple.com](http://opensource.apple.com/tarballs/objc4/)的*objc4-680.tar.gz*。

```c
class ObjcAssociation {
   uintptr_t _policy;
   id _value;
public:
   ObjcAssociation(uintptr_t policy, id value) : _policy(policy), _value(value) {}
   ObjcAssociation() : _policy(0), _value(nil) {}

   uintptr_t policy() const { return _policy; }
   id value() const { return _value; }
   
   bool hasValue() { return _value != nil; }
};

class AssociationsHashMap : public unordered_map<disguised_ptr_t, ObjectAssociationMap *, DisguisedPointerHash, DisguisedPointerEqual, AssociationsHashMapAllocator> {
public:
   void *operator new(size_t n) { return ::malloc(n); }
   void operator delete(void *ptr) { ::free(ptr); }
};

class AssociationsManager {
    static spinlock_t _lock;
    static AssociationsHashMap *_map;               // associative references:  object pointer -> PtrPtrHashMap.
public:
    AssociationsManager()   { _lock.lock(); }
    ~AssociationsManager()  { _lock.unlock(); }
    
    AssociationsHashMap &associations() {
        if (_map == NULL)
            _map = new AssociationsHashMap();
        return *_map;
    }
};

static id acquireValue(id value, uintptr_t policy) {
	// 遇见不合法policy或者assign直接返回，也就是说将其他无效policy当做assign处理
    switch (policy & 0xFF) {
    case OBJC_ASSOCIATION_SETTER_RETAIN:
        return ((id(*)(id, SEL))objc_msgSend)(value, SEL_retain);
    case OBJC_ASSOCIATION_SETTER_COPY:
        return ((id(*)(id, SEL))objc_msgSend)(value, SEL_copy);
    }
    return value;
}

inline disguised_ptr_t DISGUISE(id value) { return ~uintptr_t(value); }

void _object_set_associative_reference(id object, void *key, id value, uintptr_t policy) {
    // retain the new value (if any) outside the lock.
    // 创建一个ObjcAssociation对象
    ObjcAssociation old_association(0, nil);
    
    // 通过policy为value创建对应属性，如果policy不存在，则默认为assign
    id new_value = value ? acquireValue(value, policy) : nil;
    {
    	// 创建AssociationsManager对象
        AssociationsManager manager;
        
        // 在manager取_map成员，其实是一个map类型的映射
        AssociationsHashMap &associations(manager.associations());
        
        // 创建指针指向即将拥有成员的Class
		// 至此该类已经包含这个关联对象
        disguised_ptr_t disguised_object = DISGUISE(object);
        
         // 以下是记录强引用类型成员的过程
        if (new_value) {
            // break any existing association.
            // 在即将拥有成员的Class中查找是否已经存在改关联属性
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            if (i != associations.end()) {
                // secondary table exists
                // 当存在时候，访问这个空间的map
                ObjectAssociationMap *refs = i->second;
                // 遍历其成员对应的key
                ObjectAssociationMap::iterator j = refs->find(key);
                if (j != refs->end()) {
                	// 如果存在key，重新更改Key的指向到新关联属性
                    old_association = j->second;
                    j->second = ObjcAssociation(policy, new_value);
                } else {
                	// 否则以新的key创建一个关联
                    (*refs)[key] = ObjcAssociation(policy, new_value);
                }
            } else {
                // create the new association (first time).
                // key不存在的时候，直接创建关联
                ObjectAssociationMap *refs = new ObjectAssociationMap;
                associations[disguised_object] = refs;
                (*refs)[key] = ObjcAssociation(policy, new_value);
                object->setHasAssociatedObjects();
            }
        } else {
            // setting the association to nil breaks the association.
            // 这种情况是policy不存在或者为assign的时候
            // 在即将拥有的Class中查找是否已经存在Class
            // 其实这里的意思就是如果之前有这个关联对象，并且是非assign形的，直接erase
            AssociationsHashMap::iterator i = associations.find(disguised_object);
            if (i != associations.end()) {
            	// 如果有该类型成员检查是否有key
                ObjectAssociationMap *refs = i->second;
                ObjectAssociationMap::iterator j = refs->find(key);
                if (j != refs->end()) {
                	// 如果有key，记录旧对象，释放
                    old_association = j->second;
                    refs->erase(j);
                }
            }
        }
    }
    // release the old value (outside of the lock).
    // 如果存在旧对象，则将其释放
    if (old_association.hasValue()) ReleaseValue()(old_association);
}
```

我们读过代码后发现是其储存结构是这样的一个逻辑：


![2.png](http://upload-images.jianshu.io/upload_images/208988-67f51f426f98ce53.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


* 橙色的是`AssociationsManager`是顶级结构体，维护了一个`spinlock_t`锁和一个`_map`的哈希表。这个哈希表中的键为`disguised_ptr_t`，在得到这个指针的时候，源码中执行了`DISGUISE`方法，这个方法的功能是获得指向**self**地址的指针，即为指向**对象地址**的指针。通过地址这个唯一标识，可以找到对应的value，即一个子哈希表。（@饶志臻 勘误）
* 子哈希表是`ObjectAssociationMap`，键就是我们传入的`Key`，而值是`ObjcAssociation`，即这个成员对象。从而维护一个成员的所有属性。

在每次执行setter方法的时候，我们会逐层遍历Key，逐层判断。并且当持有Class有了关联属性的时候，在执行成员的Getter方法时，会优先查找Category中的关联成员。

这样会带来一个问题：**如果category中的一个关联对象与Class中的某个成员同名，虽然key值不一定相同，自身的Class不一定相同，policy也不一定相同，但是我这样做会直接覆盖之前的成员，造成无法访问，但是其内部所有信息及数据全部存在。**例如我们对`ViewController`做一个Category，来创建一个叫做view的成员，我们会发现在运行工程的时候，模拟器直接黑屏。


![3.jpg](http://upload-images.jianshu.io/upload_images/208988-97d8f5bde8f5de41.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)


我们在viewDidLoad中下断点，甚至无法进入debug模式。因为view属性已经被覆盖，所以不会继续进行viewController的生命周期。


![4.jpg](http://upload-images.jianshu.io/upload_images/208988-12aa766163679316.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)



这一点很危险，所以我们要杜绝覆盖Class原来的属性，这会破坏Class原有的功能。（当然，我是十分不推荐在业务项目中使用Runtime的，因为这样的代码可读性和维护性太低。）


### Getter Source Code & Remove

这两种方法我们直接看源码，在看过Setter中的遍历嵌套map结构的代码片段后，你会很容易理解这两个方法。

```c
id _object_get_associative_reference(id object, void *key) {
    id value = nil;
    uintptr_t policy = OBJC_ASSOCIATION_ASSIGN;
    {
        AssociationsManager manager;
        AssociationsHashMap &associations(manager.associations());
        disguised_ptr_t disguised_object = DISGUISE(object);
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            ObjectAssociationMap *refs = i->second;
            ObjectAssociationMap::iterator j = refs->find(key);
            if (j != refs->end()) {
                ObjcAssociation &entry = j->second;
                value = entry.value();
                policy = entry.policy();
                if (policy & OBJC_ASSOCIATION_GETTER_RETAIN) ((id(*)(id, SEL))objc_msgSend)(value, SEL_retain);
            }
        }
    }
    if (value && (policy & OBJC_ASSOCIATION_GETTER_AUTORELEASE)) {
        ((id(*)(id, SEL))objc_msgSend)(value, SEL_autorelease);
    }
    return value;
}

void _object_remove_assocations(id object) {
    vector< ObjcAssociation,ObjcAllocator<ObjcAssociation> > elements;
    {
        AssociationsManager manager;
        AssociationsHashMap &associations(manager.associations());
        if (associations.size() == 0) return;
        disguised_ptr_t disguised_object = DISGUISE(object);
        AssociationsHashMap::iterator i = associations.find(disguised_object);
        if (i != associations.end()) {
            // copy all of the associations that need to be removed.
            ObjectAssociationMap *refs = i->second;
            
            // 将所有的关联成员放到一个vector，然后统一清理
            for (ObjectAssociationMap::iterator j = refs->begin(), end = refs->end(); j != end; ++j) {
                elements.push_back(j->second);
            }
            // remove the secondary table.
            delete refs;
            associations.erase(i);
        }
    }
    // the calls to releaseValue() happen outside of the lock.
    for_each(elements.begin(), elements.end(), ReleaseValue());
}
```

另外，对于remove有一点补充。在Runtime的销毁对象函数objc_destructInstance里面会判断这个对象有没有关联对象，如果有，会调用`_object_remove_assocations`做关联对象的清理工作。

## Thinking About Hash Table

不光是本文讲述的关于Class关联对象的存储方式，还是Apple中其他的Souce Code（例如引用计数管理），我们能感受到Apple对Hash Table（本文中的map数据结构）这种数据结构情有独钟。在大量的实践中可以说明，Hash Table对于优化效率的提升，这是毋庸置疑的。

细究使用这种数据结构的原因，唯一的Key可对应指定的Value。我们从计算机存储的角度考虑，因为每个内存地址是唯一的，也就可以假象成Key，通过唯一的Key来读写数据，这是效率最高的方式。

## The End

通过阅读此文，想必你已经知道那三个问题的答案。笔者原本想对**UITableView-FDTemplateLayoutCell**进行源码分析来撰写一篇文，但是发现里面存储cell的Key值使用到了Associated Objects该技术，所以对此进行了学习探究。后面，我会分析一下**UITableView-FDTemplateLayoutCell**的源码，这些将收录在我的这个[Github仓库中](https://github.com/Desgard/iOS-Source-Probe)。


