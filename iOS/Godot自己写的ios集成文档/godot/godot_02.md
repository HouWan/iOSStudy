
> 本文开发者使用`Mac OS`开发环境，下面是在`Mac OS`处理时的过程

## Scons

`Godot`使用`Scons`构建系统。`Scons`是一个开放源码、以`Python`语言编码的自动化构建工具。
- Scons的官网：https://www.scons.org/

```bash
# 安装之前，可以先安装Xcode、Python3、Homebrew

# 注意先安装Xcode，至少也装Command Line Tools，例如：
$ xcode-select —-install

# brew官网：
# https://brew.sh/
```

这里使用`Homebrew`进行安装：
```bash
$ brew install scons
# 如果中间报错，根据报错处理即可，我在安装的时候，提示了缺少 xcode-select 环境
# 然后根据提示，安装了 xcode-select 就好了
$ xcode-select --install
$ xcode-select --version  # 查看版本，没有安装Xcode也可以装 xcode-select
```

安装`Scons`之后，可以使用下面的命令查看安装的目录和状态：
```bash
$ brew info scons
==> scons: stable 4.6.0 (bottled)
Substitute for classic 'make' tool with autoconf/automake functionality
https://www.scons.org/
/usr/local/Cellar/scons/4.6.0 (1,551 files, 19.4MB) *
  Poured from bottle using the formulae.brew.sh API on 2023-12-11 at 11:25:38
From: https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/s/scons.rb
License: MIT
==> Dependencies
Build: python-setuptools ✘
Required: python@3.12 ✔
==> Analytics
install: 3,527 (30 days), 6,568 (90 days), 15,707 (365 days)
install-on-request: 1,812 (30 days), 3,111 (90 days), 8,019 (365 days)
build-error: 35 (30 days)
```

## Godot源码

Godot的官网和GitHub地址去下载源码，下载通过`git`或者直接下载对应`Releases`源码，比如这次下载`4.1.2-stable`代码。

```bash
# 官网：
https://godotengine.org/

# GitHub仓库：
https://github.com/godotengine/godot

```

如果使用`git`拉取代码时，可以只拉取对应的分支，这样速度更快：
```bash
# You can add the --depth 1 argument to omit the commit history.
# Faster, but not all Git operations (like blame) will work.
git clone https://github.com/godotengine/godot.git

# Clone the `4.1.2-stable` tag. This is a fixed revision that will never change.
git clone https://github.com/godotengine/godot.git -b 4.1.2-stable
```

## 编译Godot

进入Godot代码根目录，代码结构如下 （分支：`4.1.2-stable`）：

```bash
$ cd godot-4.1.2-stable
$ tree -a -L 1
.
├── .clang-format
├── .clang-tidy
├── .editorconfig
├── .git-blame-ignore-revs
├── .gitattributes
├── .github
├── .gitignore
├── .lgtm.yml
├── .mailmap
├── AUTHORS.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── COPYRIGHT.txt
├── DONORS.md
├── LICENSE.txt
├── LOGO_LICENSE.md
├── README.md
├── SConstruct  # 这个文件Scons构建系统入口
├── core  # 主要核心代码
├── doc
├── drivers
├── editor  # 编辑器代码
├── gles3_builders.py
├── glsl_builders.py
├── icon.png
├── icon.svg
├── icon_outlined.png
├── icon_outlined.svg
├── logo.png
├── logo.svg
├── logo_outlined.png
├── logo_outlined.svg
├── main  # 引擎入口
├── methods.py
├── misc
├── modules
├── platform  # 各个平台适配，例如iOS、Android
├── platform_methods.py
├── scene  # Godot的组件代码，比如UI等节点
├── scu_builders.py
├── servers
├── tests
├── thirdparty
└── version.py
```

进入`cd`到代码根目录，使用`scons`构建系统，使用`scons platform=list` 可列出当前电脑环境可用的目标平台（我当前使用的Mac系统）：
```bash
$ scons platform=list

scons: Reading SConscript files ...
The following platforms are available:

        ios
        macos

Please run SCons again and select a valid platform: platform=<string>

```

使用`scons platform=xx` 开始构建，其中`platform=`可以简写为`p=`，例如

```bash
$ scons platform=ios

# ⚠️如果想使用多线程加速构建，例如加`-j`参数，例如使用6核CPU构建：
$ scons p=ios -j6

# -j6 也可以改有几个CPU就全部使用，不过编译期间可能电脑会卡
$ scons platform=ios --jobs=$(sysctl -n hw.logicalcpu)
```

> 😄构建的结果，会在根目录下的`bin/`目录下


## Scons构建参数

可以先进入Godot代码目录，使用`scons --help`看看大概有哪些参数，以及参数的解释。我第一次执行时，报错了，因为电脑没装`vulkan`，Godot4使用`vulkan`为默认渲染后端。

> Mac安装`vulkan`直接去官网下载SDK的dmg包安装即可 https://vulkan.lunarg.com/

**参数Target**

生成的二进制文件，是否包含编辑器模块，三个值：`editor`、`template_debug`、`template_release`

- `editor`：编译带有编辑器模块，默认PC目标（Linux、Windows、macOS）时，会启用，其他平台则是不启用。
- `template_debug`：带有 C++ 调试符号（C++ debugging symbols）构建
- `template_release`：不带调试符号构建

例如写法：

```bash
scons platform=ios target=editor/template_debug/template_release
```

> 😄调试符号是被调试程序的二进制信息与源程序信息之间的桥梁，是在编译器将源文件编译为可执行程序的过程中为支持调试而摘录的调试信息。调试信息包括变量、类型、函数名、源代码行等。
符号表（又称“调试符”）的作用是将十六进制数转换为源代码行、函数名及变量名。符号表中还包括程序使用的类型信息。调试器使用类型信息可以获得原始数据，并将原始数据显示为程序中所定义的结构或变量。
符号表有很多格式，比如SYM格式、PDB格式、MAP文件
使用该命令从已编译的二进制文件中删除调试符号：`strip <path/to/binary>`

带有调试符号时，编译出来的包，往往非常大，当不想要调试符号时，也可以手动指定参数：


```bash
# 其实 debug_symbols 默认就是 false
scons platform=<platform> debug_symbols=no
```

**开发和生产别名**

一般情况下，开发包需要带有调试、分析工具，生产包需要二进制文件尽可能小、可能快。 Godot 为此提供了两个别名参数：

- `dev_mode=yes`等价于`verbose=yes warnings=extra werror=yes tests=yes`，代表启用了警告作为错误的行为、并且还构建了单元测试。默认是`False`。
- `production=yes`等价于`use_static_cpp=yes debug_symbols=no lto=auto`，静态链接 `libstdc++` 可以在针对 Linux 进行编译时实现更好的二进制可移植性。当使用 MinGW 编译 Linux、Web 和 Windows 时，此别名还可以启用链接时优化，但在使用 MSVC 编译 macOS、iOS 或 Windows 时保持禁用 `LTO`。这是因为这些平台上的 `LTO` 链接速度非常慢或者生成的代码存在问题。默认是`False`。（LTO(Link Time Optimization)）

> 当使用诸如`production=yes`这种别名时，也可以再跟上参数还覆盖里面的值，比如`production=yes`，但是还想要符号表：`scons production=yes debug_symbols=yes`

**CPU架构** 比如arm64、x86_64等，例如`scons platform=ios arch=arm64`

**Dev build** `dev_build`参数主要是用于引擎开发时，配合`target`参数使用，例如禁用优化、生成调试符号、启用`assert()`等。默认是`False`。

**清理编译**之后的中间文件 两个清理的命令，根据情况，选择其中的即可：
- `scons --clean <options>`，其中`options`是之前编译的平台，比如`ios`
- `git clean -fixd` 利用git清理


## Vulkan

Godot4需要 `Vulkan` 渲染，在iOS、MacOS上，需要`MoltenVK`库。`MoltenVK`库是是 Vulkan 可移植性实现，它将高性能、行业标准的 Vulkan 图形和计算 API 的子集置于 Apple Metal 图形框架之上，使 Vulkan 应用程序能够在 macOS、iOS 和 tvOS 上运行。

😄MoltenVK的代码和编译方法如下：

- https://github.com/KhronosGroup/MoltenVK

有个偷懒不用编译`MoltenVK`的2个方法：
- 在`MoltenVK`的GitHub主页，在`Releases`里直接下载编译好的`MoltenVK-ios.tar`文件，里面有`MoltenVK.xcframework`
- 下载对应Godot的编辑器模板，里面的`iOS`工程模板里，有`MoltenVK.xcframework`
- 上面这2个是针对iOS平台的方式，安卓同理。

😄Vulkan的官网：
- https://www.lunarg.com/vulkan-sdk/
- https://vulkan.lunarg.com


