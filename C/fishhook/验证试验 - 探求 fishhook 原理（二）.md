# 验证试验 - 探求 fishhook 原理（二）

> 作者：冬瓜

> 原文链接：[Guardia · 瓜地](http://www.desgard.com/fishhook-2/)

## 示例 Demo Code

继续使用上一篇文中的代码示例：

```C
#include <stdio.h>
#include "fishhook.h"
static int (*original_strlen)(const char *_s);
int new_strlen(const char *_s) {
    return 666;
}

int main(int argc, const char * argv[]) {
    struct rebinding strlen_rebinding = { "strlen", new_strlen,
        (void *)&original_strlen };
    rebind_symbols((struct rebinding[1]){ strlen_rebinding }, 1);
    char *str = "hellolazy";
    printf("%d\n", strlen(str));
    return 0;
}
```

运行之后将其生成的执行文件拖入 *MachOView* 中。对 Mach-O 进行解析。

## Linkedit Base Address 计算


从 *MachOView* 中 *Load Commands -> LC_SEGMENT_64(__LINKEDIT)* 中获取到以下值：

![](https://diycode.b0.upaiyun.com/photo/2018/f86ae9bc39e16551633a17b329ba49f2.jpg)

进行下列*式(1)*和*式(2)*的计算：


$$
\begin{equation}
\left\{
\begin{array}{l@{\;=\;}l}
vmaddr=1000030000_{(hex)}\\
file\ offset=30000_{(hex)}
\end{array}
\right.
\end{equation}
$$

$$
\begin{equation}
\begin{aligned}
base\_address&=slide+vmaddr-file\ offset \\
&=slide+1000000000_{(hex)}
\end{aligned}
\end{equation}
$$

## 符号表、字符表和跳转表

继续看上文的这张图片：

![](https://diycode.b0.upaiyun.com/photo/2018/76aab6244569b2be67b64c3c4b88b45b.jpg)

此时，我们已经获取到了 *Base Address*，根据之前的流程，需要找到 *__LINKEDIT Section* 中的 Symbols 表、Indirect Symbols 表和 String 字符串表，这些地址我们需要在 Load Commands 中来获取。找到 *LC_SYMTAB* 和 *LC_DYSYMTAB* 这两个 Commaneds。

![](https://diycode.b0.upaiyun.com/photo/2018/1b7a95521a9c8c8cf679d397f9dff302.jpg)


![](https://diycode.b0.upaiyun.com/photo/2018/78d3a4b9139be62b6a25369470ea4d59.jpg)


$$
\begin{equation}
\left\{
\begin{array}{l@{\;=\;}l}
symbol\_offset=symtab\_cmd\to symoff=12680_{(oct)}=3188_{(hex)}\\
indirect\_symbol\_offset=dysymtab\_cmd\to symoff =14008_{(oct)}=35B8_{(hex)}\\
string\_table\_offset=symtab\_cmd\to stringoff=13864_{(oct)}=3628_{(hex)}
\end{array}
\right.
\end{equation}
$$

$$
\begin{equation}
\left\{
\begin{array}{l@{\;=\;}l}
symbol\_base=base\_address+symbol\_offset=slide+100003188_{(hex)}\\
indirect\_symbol\_base=base\_address+indirect\_symbol\_offset=slide+1000035B8_{(hex)}\\
string\_table\_base=base\_address+string\_table\_offset=slide+100003628_{(hex)}
\end{array}
\right.
\end{equation}
$$


![](https://diycode.b0.upaiyun.com/photo/2018/f3846df367c1c69f25eebe7ab79d4101.jpg)

![](https://diycode.b0.upaiyun.com/photo/2018/d3c25d286d0bf7ab3baf07acabe6d28b.jpg)

![](https://diycode.b0.upaiyun.com/photo/2018/2e24a8f940d9c299a016226953fd9c0f.jpg)


## 跳转表 nl 和 la 绑定符号基址

我们在 MachOView 中验证了三个表的位置。之后继续跟随着 fishhook 的思路来进行验证。下面将进入二尺遍历 Load Command 流程。这一次需要拿出的 Command 是 *LC_SEGMENT(__DATA)*，目的是为了找到 `__nl_symbol_ptr` 和 `__la_symbol_ptr` 这两个 Section 的位置。

$$
\begin{equation}
\left\{
\begin{array}{l@{\;=\;}l}
nl\_indirect\_sym\_index=13_{(oct)}\\
la\_indirect\_sym\_index=15_{(oct)}\\
\end{array}
\right.
\end{equation}
$$

$$
\begin{equation}
\left\{
\begin{array}{l@{\;=\;}l}
nl\_sym\_base\_addr&=nl\_indirect\_sym\_index\times size+indirect\_symbol\_base\\
&=13_{(oct)}\times 4 + (1000035B8_{(hex)}+slide)=1000035EC_{(hex)}+C\\
la\_sym\_base\_addr&=la\_indirect\_sym\_index\times size+indirect\_symbol\_base\\
&=15_{(oct)}\times 4 + (1000035B8_{(hex)}+slide)=1000035F4_{(hex)}+C\\
\end{array}
\right.
\end{equation}
$$

这里的 C 其实是上方 slide 常量的运算结果，由于在这个场景下 MachOView 验证时发现 `slide = 0`，但不意味着 `slide` 是一个恒为 0 的值。`vmaddr_slide` 的取值其实是**地址空间布局随机化（ASLR）**机制的结果，这是一种针对缓冲区溢出的安全保护技术，这里不再赘述。

![](https://diycode.b0.upaiyun.com/photo/2018/9d136ba97927863fa3e2a675e8ee8d95.jpg)


根据 *Indirect Symbols* 中的描述，发现下标标识的区域的起始位置与我们的计算相吻合，此处也再次验证成功。在 *Indirect Symbols* 的结构中，我们可以找到其 *Lazy Symbol Pointer*。例如，我们在代码中出现的 `strlen` 方法：

![](https://diycode.b0.upaiyun.com/photo/2018/09ab382c46526f986d37b25ec27185cb.jpg)

![](https://diycode.b0.upaiyun.com/photo/2018/2cf3651bb443e051f7fa3ca950b2b889.jpg)

## 在符号表中获取全部信息

在 `Lazy Symbol Pointers` 这里，我们最终获取到了 `0x10002068 -> _strlen` 这个值。它起始是对于当前 `_strlen` 方法在符号表中的一个映射，我们可以简单的理解为**它就是在符号表中对应方法的下标**。

这个结论虽然至今笔者无法跟踪代码，将其结构实例化，但是可以通过 fishhook 的源码进行分析得出结论。

```C
...
// 这里直接将 Lazy Symbol Point 的一个内容强转为二阶指针
// 也就是说明每个 Lazy Symbol Point 也是一个指针（当然从命名中也能猜出）
void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
...
// 在遍历每一个内容的时候，先拿出其对应的 index
uint32_t symtab_index = indirect_symbol_indices[i];
// 之后直接从符号表中用下标访问的方法来获取信息
uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
```

`symtab[symtab_index].n_un.n_strx` 从这个获取的方式来看，`symtab_index` 处的位置对应的是某个符号表的基址位，因此可以将类型转成 `nlist_64`。

```C
struct nlist_64 {
    union {
        uint32_t  n_strx; /* 符号表中的位置 */
    } n_un;
    uint8_t n_type;        /* 经过掩码处理，表示重定义符号不同的种类 */
    uint8_t n_sect;        /* section 的编号 */
    uint16_t n_desc;       /* 类似于 n_type 经过掩码处理，用来定义一些性质 */
    uint64_t n_value;      /* 记录信息的特殊值 */
};
```

为什么在 fishhook 源码中可以将符号名称直接通过 `char *symbol_name = strtab + strtab_offset;` 直接取得呢？因为在 String Table 存储过程中会在每一个符号名的末尾增加不确定个 `\0`，而在 C 中一次的字符数组获取会以 `\0` 为结束。在 MachOView 中已经将符号名进行了解析，我们可以清晰的在解析后的 `nlist` 结构中发现符号名：

![](https://diycode.b0.upaiyun.com/photo/2018/a4c5c512f0ac0e645865950cfb4cc41e.jpg)

此时我们已经找到了改符号表的位置，剩下的工作仅需将 `Lazy Symbol Pointers` 中对应的指针进行指向变更即可完成操作。我在 fishhook 中加入了部分输出验证代码，可以大致验证这一地址的更变，但是由于在运行时有着 ASLR 的参与，是无法精准的将地址完全与 MachOView 的解析结果精准比对，但是从地址的大致区域中可以看出这个操作的成功性，以下是加入代码和输出的 log：

```C
static void perform_rebinding_with_section(struct rebindings_entry *rebindings,
                                           section_t *section,
                                           intptr_t slide,
                                           nlist_t *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab) {
    // 在 Indirect Symbol 表中检索到对应位置
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    // 获取 _DATA.__nl_symbol_ptr(或__la_symbol_ptr) Section
    // 已知其 value 是一个指针类型，整段区域用二阶指针来获取
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
    // 用 size / 一阶指针来计算个数，遍历整个 Section
    for (uint i = 0; i < section->size / sizeof(void *); i++) {
        // 通过下标来获取每一个 Indirect Address 的 Value
        // 这个 Value 也是外层寻址时需要的下标
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL   | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        // 获取符号名在字符表中的偏移地址
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        // 获取符号名
        char *symbol_name = strtab + strtab_offset;
        // 过滤掉符号名小于 4 位的符号
        if (strnlen(symbol_name, 2) < 2) {
            continue;
        }
        // 取出 rebindings 结构体实例数组，开始遍历链表
        struct rebindings_entry *cur = rebindings;
        while (cur) {
            // 对于链表中每一个 rebindings 数组的每一个 rebinding 实例
            // 依次在 String Table 匹配符号名
            for (uint j = 0; j < cur->rebindings_nel; j++) {
                // 符号名与方法名匹配
                if (strcmp(&symbol_name[1], cur->rebindings[j].name) == 0) {
                    // 如果是第一次对跳转地址进行重写
                    if (cur->rebindings[j].replaced != NULL &&
                        indirect_symbol_bindings[i] != cur->rebindings[j].replacement) {
                        // 记录原始跳转地址
                        *(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];
                    }
                    // 重写跳转地址
                    indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
                    // 完成后不再对当前 Indirect Symbol 处理
                    // 继续迭代到下一个 Indirect Symbol
                    
                    /** 加入调试代码 **/
                    printf("\n\nSymbol Name: %s\n", &symbol_name[1]);
                    printf("Rebinding Name: %s\n", cur->rebindings[j].name);
                    printf("Origin Addr: 0x%X\n", cur->rebindings[j].replaced);
                    printf("Rebinding Addr: 0x%X\n", cur->rebindings[j].replacement);
                    /** 调试代码 END **/
                    goto symbol_loop;
                }
            }
            // 链表遍历
            cur = cur->next;
        }
    symbol_loop:;
    }
}
```

```shell
Symbol Name: strlen
Rebinding Name: strlen
Origin Addr: 0x20A0
Rebinding Addr: 0x1DA0
666
Program ended with exit code: 0
```

`0x1DA0` 这个地址在原始的间接表指向的位置之前，所以我们大致断定它处在 `_TEXT` 段。并且`__stub_helper`, `__cstring`, `__unwoind_info` 这些 Session 是我们无法直接干预的位置，所以可以猜测 `0x1DA0` 落在我们的 `__text` Session 中。我们掏出 Hopper 来验证一下这个猜想，发现正是如此：

![](https://diycode.b0.upaiyun.com/photo/2018/6eb46dbda7214a22ad5e2e3c39bbd28b.jpg)


## 尾声

fishhook 的原理探究至此就告一段落。通过这个源码探求，强化了对于 Mach-O 的学习和认识，也在之中学习到了 Facebook 对于 Hook C 方法这个很妙的技巧。最后不得不再惊叹一句，FB 真的是令技术人向往的地方。

## 参考

* [nlist-Mach-O文件重定向信息数据结构分析](http://turingh.github.io/2016/05/24/nlist-Mach-O%E6%96%87%E4%BB%B6%E9%87%8D%E5%AE%9A%E5%90%91%E4%BF%A1%E6%81%AF%E6%95%B0%E6%8D%AE%E7%BB%93%E6%9E%84%E5%88%86%E6%9E%90/)
* [地址空间布局随机化(ASLR)机制的分析与绕过](http://blog.c0smic.cn/2017/04/18/aslr/)





