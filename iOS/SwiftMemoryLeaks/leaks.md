## 前言
声明：本文非原创，是我翻译文章。感谢作者`Kenny Dubroff`，如有侵权，请联系删除。

原文链接：https://blog.devgenius.io/unit-testing-memory-leaks-265f8d9777fb
原文作者：`Kenny Dubroff`

## 正文

在 Swift 中，我们通过 ARC 非常高效地处理内存。基本上，引用对象（例如类`class`）会记录它们被引用的次数（引用计数）。当计数达到 0 时，该对象被标记为释放，并在系统需要空间时从内存中移除。

如果我们不小心，比如创建了一个引用循环，那么我们就会遇到内存空间永远不会被标记为释放的情况。不幸的是，对我们来说，追踪这些可能非常棘手。

在本教程中，您将实现一个单元测试，它可以测试任何对象用于查看它是否被正确地释放。

有关内存管理、循环引用以及如何避免它们的更多信息，可以查看我的另一篇文章：

[Swift循环引用之Weak和Unowned](https://blog.devgenius.io/retain-cycles-and-weak-vs-unowned-643c676821fc)

### 常见的循环引用

一个常见循环引用的地方就是，当我们在闭包(closure)中捕获`self`。本质上，`self`持有闭包，那么如果闭包内调用`self`，则闭包具有对`self`的引用。他们互相指着对方，所以很有可能他们都不会被释放。

创建一个包含单元测试的新项目，你可以使用默认的`ViewController`或者创建一个自己的，我们准备开始写代码。

**我是图片002**
**我是图片002**

在`ViewController`中，定一个闭包，并在闭包的实现中进行整数相加操作。注意确保实现所需的`init`初始化。

```swift
class ViewController: UIViewController {

    var numberOfTimes = 0

    private var closure: (() -> Void) = { }

    init() {
        super.init(nibName: nil, bundle: nil)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        countIt()
    }

    func commonInit() {
        self.closure = {
            self.numberOfTimes += 1
            print(self.numberOfTimes)
        }
    }

    func countIt() {
        closure()
    }
}
```

在闭包中，如果你在`numberOfTimes`之前没有加`self.`，编译器会给你一个关于捕获语义的错误。编译器需要让您在此处显示声明引用对象，并提醒您可能在创建一个循环引用。在这里打破循环引用是很容易的事情，我们将在文本后面介绍。但是现在，我们故意产生内存泄漏💧。

**让我们开始证明这里有循环引用**

打开`YourProjectNameTests.swift`，你会看到一些模板代码，删除这些代码，并创建一个`testRetainCycle`方法，如下图：

**我是图片3**
**我是图片3**

通过创建`ViewController`的实例、运行`countIt()`方法，并断言它`numberOfTimes`为 1 来测试您的方法是否有效。
```swift
func testRetainCycle() {
    let vc = ViewController()

    vc.countIt()
    XCTAssertEqual(vc.numberOfTimes, 1)
}
```

**通过单击方法左侧旁边的菱形运行测试，测试应该是通过的**

现在你需要做的是证明`vc`在测试方法运行之后应该为`nil`。因为`vc`只在测试代码块中有效，如果`vc`不为`nil`说明存在循环引用。

在单元测试中，类`XCTestCase`有2个特殊方法`setup()`和`teardown()`，这2个方法分别在每次测试之前和之后调用。要检查循环引用/内存泄漏，您只需检查您的实例是否在测试运行后被释放。

> `setup()`一般初始化测试所需的资源，`teardown()`一般用于测试结束释放资源

虽然类`XCTestCase`有一个`teardown()`方法，但是在这里，我们需要使用`addTearDownBlock(:)`方法，这个特殊的方法会在测试方法结束后，类`XCTestCase`的`teardown()`方法之前调用，并且在同一个测试方法中，可以多次调用`addTearDownBlock(:)`，执行的顺序按照`LIFO`(last in first out)原则执行。需要注意的地方是，可以在方法`setup()`期间调用此方法，但是不能在`tearDown()`方法中调用此方法。

现在我们在`addTeardownBlock()`方法闭包中进行断言`vc`是`nil`：

```swift
func testRetainCycle() {
    let vc = ViewController()

    vc.countIt()
    XCTAssertEqual(vc.numberOfTimes, 1)

    addTeardownBlock {
        XCTAssertNil(vc)
    }
}
```

运行测试，结果是失败的！和其他闭包一样，这里`self`持有`addTeardownBlock`，然后在闭包中检查`vc`是否为`nil`，并且`vc`是在闭包之前创建的局部变量，指向堆空间的`ViewController`，所以现在闭包和`vc`通过局部变量互相指向，这是一个循环引用...

### 打破循环引用

我之前说过，打破循环引用是非常容易的。Swift闭包带有捕获列表。在捕获列表中，我们声明要在闭包中使用的外部对象，并可以添加属性修饰符。所以我们可以`weakify`我们的`vc`属性，像这样：`addTearDownBlock { [weak vc] in`。由于弱引用不增加引用计数，所以就打破了循环引用。

```swift
func testRetainCycle() {
    let vc = ViewController()

    vc.countIt()
    XCTAssertEqual(vc.numberOfTimes, 1)

    addTeardownBlock { [weak vc] in
        XCTAssertNil(vc)
    }
}
```

但是如果你运行单元测试，它仍然失败。这是为什么？

好吧，我们只解决了一个循环引用——我们刚刚创建的单元测试中的一个。我们还要回到`ViewController`，并在`countIt()`方法中弱引用`self`，但是当你这么做时，你应该得到几个编译器错误。这是因为`self`现在是`Optional`(可选的)，为了避免这种情况，你可以选择使用`unowned`，但是通常使用`weak`是更安全的选择。(`unowned`类似强制展开)

您可以随意解包`self`，但如果您强制解包，那还不如直接使用`unowned`. 这里我选择可​​选链。但是在这里，`self`持有闭包并且不涉及其他类，所以使用`unowned`也是安全的。

**我是图片44**
**我是图片44**

```swift
class ViewController: UIViewController {

    var numberOfTimes = 0

    private var closure: (() -> Void) = { }

    init() {
        super.init(nibName: nil, bundle: nil)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        countIt()
    }

    func commonInit() {
        self.closure = { [weak self] in
            self?.numberOfTimes += 1
            print(self?.numberOfTimes)
        }
    }

    func countIt() {
        closure()
    }
}
```

最后，如果您运行单元测试，会发现循环引用已断开。现在您知道了创建和断开循环引用都是多么容易。

**我是图片5**
**我是图片5**

### 让它可重复使用

在上面的代码中，我们仅测试了`vc`一个对象，但是如果您有很多引用对象，并且想确保没有在代码的其他地方造成循环引用怎么办？多亏了`XCTAssert`的两个可选参数`file`和`line`，这样我们就能封装代码，并能让错误提示到正确的文件和行数。

在`testRetainCycle`方法之后，添加一个封装代码如下:
```swift
private func assertNoMemoryLeak(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
    addTeardownBlock { [weak instance] in
        XCTAssertNil(instance, "⚠️发现潜在的循环引用", file: file, line: line)
    }
}
```

在需要检测循环的地方，用此方法替换`addTearDownBlock`：
```swift
func testRetainCycle() {
    let vc = ViewController()

    vc.countIt()
    XCTAssertEqual(vc.numberOfTimes, 1)

    assertNoMemoryLeak(vc, file: #filePath, line: #line)
}
```

发生循环引用(内存泄漏)最常见的地方之一就是在`ViewController`使用HTTP网络请求。所以下一步，您可以尝试在异步的网络请求方法中，创建一个循环引用，并打破循环引用。





