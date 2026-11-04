## 1. Combine基础概念

### 1.1 Combine 的三个核心角色

把 Combine 想象成一条数据传输管道：
![Combine](./images/0001.webp)

> 不过，严格来说，Publisher 和 Subscriber 之间还有一个重要角色：`Subscription`，负责连接、请求数据和取消订阅，后面会深入。

![Combine](./images/0002.webp)


#### 1.1.1 Publisher（发布者）

Publisher 是一个数据源，负责产生数据或事件。

常见例子：

- 输入框内容变化。
- 网络请求结果。
- 通知。
- 定时器。
- 对象属性变化。

#### 1.1.2 Operator（操作符）

负责处理 Publisher 输出的数据。

例如：

- `map`：转换数据。
- `filter`：过滤数据。
- `debounce`：防抖。
- `combineLatest`：合并多个数据源。
- `retry`：失败重试。

> 大多数 Operator 会创建一个新的 Publisher。

#### 1.1.3 Subscriber（订阅者）

负责接收最终数据。

最常见的就是：

```swift
.sink { value in
    print(value)
}
```

> `sink` 一个多义词，作名词时主要指厨房或卫生间的洗涤槽（水槽），也可指“污水坑”或“沉降池”；作动词时意为“下沉、沉没、下降”。

`sink(receiveCompletion:receiveValue:)` 是 Combine 里最基础的**订阅方式**。它把 Publisher 发出的两类事件分别交给两个闭包处理：

| 闭包 | 接收的事件 | 调用次数 | 含义 |
| :--- | :--- | :--- | :--- |
| **`receiveValue`** | 数据值（`Output`） | 0 ～ 多次 | "流里来了一个新值" |
| **`receiveCompletion`** | 完成事件（`Subscribers.Completion`） | **最多 1 次** | "流结束了，原因是成功或失败" |

任何 Publisher 对订阅者只会发出两类事件：

```
Publisher ──►  value, value, value, ...  ──►  completion
                (0~N 个值)                    (最多 1 次，且之后不再有值)
```

`completion` 又有两种：

```swift
enum Subscribers.Completion<Failure> {
    case finished          // 正常结束，没有错误
    case failure(Failure)  // 以错误结束
}
```

所以 `sink` 本质上是：

```swift
.sink(
    receiveCompletion: { [weak self] completion in
        // 流终止时调用一次
        // completion 要么是 .finished，要么是 .failure(error)
         switch completion {
          case .finished:
            print("流正常结束")
            // 停止 loading、标记请求完成、触发下一步流程等
          case .failure(let error):
            print("流以错误结束：\(error)")
            // 弹错误提示、记录日志、重试、降级展示、停止 loading 动画。
         }
         // 比如 关闭连接、取消计时器、恢复按钮可点击状态。
    },
    receiveValue: { [weak self] value in
        // 每来一个值调用一次
        // 比如更新UI、写入 ViewModel 、播放动画、埋点、跳转、刷新 table、切换页面状态。
    }
)
```

> **关键顺序规则**：`receiveCompletion` 一旦被调用，这个订阅就结束了，之后**不会再有 `receiveValue`**。`.finished` 和 `.failure` 二者只会出现一个。

在 UI 场景中，一个典型模式是：
```swift
.receiveCompletion: { [weak self] completion in
    self?.stopLoading()          // 无论成功失败都要收尾
    if case .failure(let error) = completion {
        self?.showError(error)   // 只有失败才提示
    }
}
```

##### ① `.receive(on:)` 对两个闭包都生效

```swift
.receive(on: DispatchQueue.main)
.sink(receiveCompletion: ..., receiveValue: ...)
```

`receive(on:)` 是**下游操作符**，它把后续所有事件（包括 completion）都切到主线程。所以 `receiveCompletion` 里也可以安全更新 UI。你注释里写"URLSession 的结果不保证在主线程"是对的——`URLSession.DataTaskPublisher` 默认在后台队列发事件，不加 `receive(on:)` 直接改 UI 会崩溃或警告。

##### ② `sink` 有两个重载，别混淆

```swift
// 版本 A：Failure 为 Never 时可用，只处理值
publisher.sink { value in ... }

// 版本 B：完整版，两个闭包都处理
publisher.sink(receiveCompletion: { ... }, receiveValue: { ... })
```

##### ③ 不 `store` 就立即取消

```swift
.sink(...)
.store(in: &cancellables)
```

`sink` 返回 `AnyCancellable`。如果不保存，它会在语句结束时被释放，订阅立即取消，**两个闭包都不会执行**。这是初学者最常见的"为什么没反应"原因。


##### ④ `receiveCompletion` 之后 `AnyCancellable` 仍然存在

流结束后，`cancellables` 里的那个 token 并不会自动移除，它只是处于"已完成"状态。再次调用 `loadPost()` 会创建**新的**订阅和新的 token。如果频繁请求，旧 token 会一直堆积在 `Set` 里（虽然已失效）。需要精细管理时，可以在 completion 里手动移除，或者用 `assign`/`sink` 返回的 token 做键管理。


### 1.2 第一个 Combine 示例：Just

`Just` 是最简单的 Publisher。

它向每个订阅者发送一个值，然后正常结束。

```swift
import Combine

// 创建一个只发送一次数据的 Publisher
let publisher = Just("Hello Combine")

// 建立订阅
let cancellable = publisher.sink { value in
    print("收到数据：\(value)")
}
```

虽然这个例子中, Combine只是发送一个值，但是 Combine 的价值不是发送一个值，而是**组合持续变化的数据流，并且统一管理事件、错误、取消和完成状态**。


### 1.3 Publisher 的 Output 和 Failure

这是理解 Combine 类型系统最重要的知识点。

Publisher 协议的核心是两个关联类型：

```swift
protocol Publisher<Output, Failure> {

    associatedtype Output

    associatedtype Failure: Error

    // ...
}
```


你可以理解为：

```swift
Publisher<输出的数据类型, 可能的错误类型>
```

例如：

```swift
Just<Int>
```

其概念上的类型为：

```swift
Output = Int
Failure = Never
```

`Never` 表示这个 Publisher 不会以失败结束。

网络请求则可能是：

```swift
Output = Data
Failure = URLError
```

> 注意，这里只有两个类型维度，并不表示 Publisher 必然只发送一次数据。

一个 Publisher 可以发送零个、一个或者多个 Output，最后正常结束或失败结束；一些持续事件流也可能长期不结束。

### 1.4 Completion：完成与失败

Combine 的流有两类终止事件：

```swift
Subscribers.Completion<Failure>
```

包含：

```swift
.finished
.failure(error)
```

看一个完整示例：

```swift
import Combine
import Foundation

enum DemoError: Error {
    case networkError
}

// 创建一个手动发送数据的 Publisher
let subject = PassthroughSubject<Int, DemoError>()

// 保存订阅，避免马上被释放
let cancellable = subject.sink(
    receiveCompletion: { completion in
        switch completion {

        case .finished:
            print("数据流正常结束")

        case .failure(let error):
            print("数据流发生错误：\(error)")
        }

    },
    receiveValue: { value in
        print("收到数据：\(value)")
    }
)

// 连续发送两个值
subject.send(10)
subject.send(20)

// 发送完成事件
subject.send(completion: .finished)

// 完成之后再发送，订阅者不会收到
subject.send(30)
```

输出：

```
收到数据：10
收到数据：20
数据流正常结束
```

> 记住：Completion 是终止事件，一旦完成，当前订阅就不会再接收后续值。

这一点对网络错误处理尤其重要。

例如搜索框是一个长期存在的事件流，如果某次网络错误直接传递到整条搜索流的末端，那么整个订阅可能失败结束，之后用户继续输入也不会触发搜索。

因此，实际项目通常要在每次网络请求的内部处理错误，而不是让单次请求失败终止整个搜索事件流。


### 1.5 AnyCancellable：订阅生命周期

这是初学 Combine 最容易出错的地方。

一般在 UIViewController 内这样管理：

```swift
import UIKit
import Combine

final class DemoViewController: UIViewController {

    // 保存当前控制器的订阅
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        Just(100)
            .sink { value in
                print(value)
            }
            .store(in: &cancellables)
    }
}
```

为什么要 `store(in:)`？

因为 `sink` 返回一个 `AnyCancellable`。

它代表取消订阅的句柄，当这个句柄被释放时，会自动调用取消逻辑。

对于网络、通知、Timer 等长期或异步订阅，这非常重要。

如果你想主动取消：

```swift
// 清空所有订阅
cancellables.removeAll()
```

也可以保存单独的句柄：

```swift
private var requestCancellable: AnyCancellable?

// 然后：

requestCancellable?.cancel()
requestCancellable = nil
```

需要区分：

- 正常完成：Publisher 发出 `.finished`。
- 错误结束：Publisher 发出 `.failure`。
- 主动取消：通常不会向下游额外发送 `.finished`。

### 1.6 关于内存泄漏

下面的写法在长期订阅中可能形成循环引用：

```swift
publisher
    .sink { value in
        self.updateUI(value)
    }
    .store(in: &cancellables)
```

对象关系可能变成：

```swift
ViewController
    ↓ 持有
AnyCancellable
    ↓ 订阅链持有 Closure
Closure
    ↓ 强引用
ViewController
```

因此，UIKit 控制器里通常使用：

```swift
publisher
    .sink { [weak self] value in
        self?.updateUI(value)
    }
    .store(in: &cancellables)
```

> 这不是说任何 Combine Closure 都必须使用 weak self，而是要根据订阅生命周期与对象所有权分析。对长期存在的通知、状态流和定时器尤其需要注意。

## 2.Publisher 类型与常用 Operator

### 2.1 常用的 Publisher 类型

| Publisher                      | 特点               | 适用场景           |
| ------------------------------ | ---------------- | -------------- |
| `Just`                         | 发送一个值后结束         | 默认值、简单测试       |
| `Empty`                        | 不发送值，可直接结束       | 空结果分支          |
| `Fail`                         | 立即发送错误           | 参数错误、校验失败      |
| `Future`                       | 异步产生一次结果         | 包装一次性回调 API    |
| `Deferred`                     | 延迟创建 Publisher   | 延迟执行副作用        |
| `PassthroughSubject`           | 手动发送事件，不保存最新值    | 按钮、刷新、通知       |
| `CurrentValueSubject`          | 保存当前值，新订阅者先收到当前值 | 当前状态、配置        |
| `@Published`                   | 属性变化自动发布         | 页面状态、ViewModel |
| `URLSession.DataTaskPublisher` | 发送网络请求结果         | HTTP 请求        |
| `NotificationCenter.Publisher` | 将通知变为数据流         | 键盘、生命周期、系统事件   |


> `Subject` 是 `Publisher` 的一种"特殊子类型"——所有 `Subject` 都是 `Publisher`，但 `Publisher` 不一定是 `Subject`。区别只在于：`Subject` 允许你手动 `send` 事件，而普通 `Publisher` 不行。

源码结构：
```swift
Publisher（协议，顶层抽象）
    └── Subject（协议，继承自 Publisher）
            ├── PassthroughSubject（具体类）
            └── CurrentValueSubject（具体类）

public protocol Subject: AnyObject, Publisher {
    func send(_ value: Output)
    func send(completion: Subscribers.Completion<Failure>)
}
```


- `Just`、`Future`、`URLSession.DataTaskPublisher` 等：只是 `Publisher`，它们的数据由内部逻辑产生，你无法从外部塞值进去。
  - 类似：水管的出水口	你只能接水（订阅），不能往里倒水
- `PassthroughSubject`、`CurrentValueSubject`：既是 `Publisher` 又是 `Subject`，你既可以把它们当数据流订阅，也可以主动 `send` 新值。
  - 类似：水龙头 + 出水口	你既能接水（订阅），也能拧开往里倒水（send）

![Combine](./images/0003.webp)

### 2.2 PassthroughSubject：事件型 Publisher

可以将它理解为一个手动发送的事件通道。它适合描述「事件发生了」，**比如用户点击刷新、请求登录、页面需要重新加载**。

```swift
import Combine

let subject = PassthroughSubject<String, Never>()

let cancellable = subject.sink { value in
    print("收到：\(value)")
}

subject.send("点击登录")
subject.send("点击刷新")
subject.send("点击退出")

// 输出：
// 收到：点击登录
// 收到：点击刷新
// 收到：点击退出
```

> 特别注意：`PassthroughSubject` 不会保存历史值。

例如：

```swift
let subject = PassthroughSubject<Int, Never>()

// 没有订阅者，这个值不会被缓存
subject.send(10)

let token = subject.sink {
    print($0)
}

subject.send(20)

// 只会输出 20
```

### 2.3 CurrentValueSubject：状态型 Publisher

它与 `PassthroughSubject` 最大的区别是：有一个当前值。

```swift
let score = CurrentValueSubject<Int, Never>(0)

score.send(100)

// 新订阅者会先收到当前值 100
let token = score.sink { value in
    print("当前分数：\(value)")
}

score.send(200)

// 输出：
// 当前分数：100
// 当前分数：200
```

你还可以直接读取或者修改：

```swift
print(score.value)  // 读取

score.value = 300  // 修改
```

它适合表示：

- 当前选中的套餐。
- 当前登录状态。
- 当前筛选条件。
- 当前页面配置。

### 2.4 两种 Subject 怎么选？

| 需求        | 推荐                               |
| --------- | -------------------------------- |
| 用户点击了一次刷新 | `PassthroughSubject`               |
| 用户当前是否登录  | `CurrentValueSubject`              |
| 某个操作发生了一次 | `PassthroughSubject`               |
| 当前搜索关键词   | `CurrentValueSubject` / `@Published` |
| 列表当前筛选状态  | `CurrentValueSubject` / `@Published` |

你可以记住这个简单原则：

事件用 `PassthroughSubject`，状态用 `CurrentValueSubject` 或 `@Published`。

### 2.5 @Published：属性变化自动发布

如果你已有一个 `Model` 或 `Controller`，想让属性变化自动通知订阅者，可以这样写：

```swift
import Combine

final class UserState {
    // 每次赋值会发布变化
    @Published var nickname = "Guest"

    @Published var isVIP = false
}
```

监听：

```swift
let user = UserState()

// 注意，这里是写法是 $nickname，不是 nickname
// 因为 `nickname` 是属性名，而 `$nickname` 是属性的发布者
let token = user.$nickname.sink { nickname in
    print("昵称变化：\(nickname)")
}

user.nickname = "Alice"
user.nickname = "Bob"

// 输出：
// 昵称变化：Guest
// 昵称变化：Alice
// 昵称变化：Bob
```

此外，`@Published` 的发布发生在属性设置过程中，具有 willSet 语义。因此在订阅回调里优先使用收到的 `nickname` 参数，不要假设立即读取 `user.nickname` 已经得到新值。

### 2.6 常用 Operator 速查

| Operator              | 功能                  | 使用频率 |
| --------------------- | ------------------- | ---- |
| `map`                 | 转换值                 | 极高   |
| `compactMap`          | 转换并过滤 nil           | 高    |
| `filter`              | 筛选满足条件的值            | 极高   |
| `removeDuplicates`    | 去掉连续重复值             | 高    |
| `debounce`            | 等输入平稳后再发送           | 极高   |
| `throttle`            | 限制发送频率              | 高    |
| `combineLatest`       | 组合多个数据源的最新值         | 极高   |
| `zip`                 | 按顺序配对不同数据源的值        | 中    |
| `merge`               | 合并相同类型的数据流          | 中    |
| `flatMap`             | 将值映射为 Publisher 并合并 | 高    |
| `switchToLatest`      | 只保留最新的内层 Publisher  | 高    |
| `catch`               | 失败时切换到替代 Publisher  | 高    |
| `replaceError`        | 失败时提供默认值            | 高    |
| `retry`               | 失败后重新订阅             | 中    |
| `receive(on:)`        | 调度下游接收              | 极高   |
| `subscribe(on:)`      | 调度上游订阅等操作           | 中    |
| `handleEvents`        | 观察订阅和取消等事件          | 中    |
| `share`               | 多订阅者共享一个上游          | 中    |
| `eraseToAnyPublisher` | 隐藏复杂 Publisher 类型   | 高    |

使用 `map`、`filter`、`removeDuplicates` 代码示例
```swift
import Combine

let subject = PassthroughSubject<Int, Never>()

let token = subject
    // 只处理正数
    .filter { $0 > 0 }

    // 去除连续相同的数字
    .removeDuplicates()

    // 转换成字符串
    .map { "当前值：\($0)" }

    // 最后接收
    .sink { value in
        print(value)
    }

subject.send(-1)  // 被过滤
subject.send(10)  // 输出
subject.send(10)  // 连续重复，被过滤
subject.send(20)  // 输出

结果：
// 当前值：10
// 当前值：20
```

> 特别注意：`removeDuplicates()` 只去除相邻的连续重复值，不是对历史所有值进行全局去重。

## 3.UIKit + Combine 实战

### 3.1 监听 UITextField 输入并校验登录表单

案例需求：
- 用户输入用户名和密码。
- 用户名至少 3 个字符。
- 密码至少 6 个字符。
- 两个条件都成立时，登录按钮可点击。
- 不使用 Delegate 手动计算每次表单状态。

传统 MVC 通常会为两个输入框添加 target-action，然后调用同一个 `updateLoginButton()`。

Combine 可以将两个输入事件组合起来，自动计算登录状态。

```swift
// import UIKit 、Combine、SnapKit

final class LoginViewController: UIViewController {
    
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    
    // 输入事件由 Subject 管理
    private let usernameSubject =
        CurrentValueSubject<String, Never>("")
    private let passwordSubject =
        CurrentValueSubject<String, Never>("")
    
    // 存储 AnyCancellable
    private var cancellables = Set<AnyCancellable>()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupUI()
        setupConstraints()
        bindInputs()
    }
    
    private func setupUI() {
        usernameField.placeholder = "用户名"
        usernameField.borderStyle = .roundedRect

        passwordField.placeholder = "密码"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true

        loginButton.setTitle("登录", for: .normal)
        loginButton.backgroundColor = .systemBlue
        loginButton.tintColor = .white
        loginButton.layer.cornerRadius = 10
        loginButton.isEnabled = false
        
        view.addSubview(usernameField)
        view.addSubview(passwordField)
        view.addSubview(loginButton)
        
        // UIKit 输入事件发送到 Subject
        usernameField.addTarget(self, action: #selector(usernameChanged), for: .editingChanged)
        passwordField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)
    }
    
    private func setupConstraints() {
        usernameField.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(80)
            make.leading.trailing.equalToSuperview().inset(25)
            make.height.equalTo(50)
        }
        
        passwordField.snp.makeConstraints { make in
            make.top.equalTo(usernameField.snp.bottom).offset(16)
            make.leading.trailing.equalTo(usernameField)
            make.height.equalTo(50)
        }
        
        loginButton.snp.makeConstraints { make in
            make.top.equalTo(passwordField.snp.bottom).offset(24)
            make.leading.trailing.equalTo(usernameField)
            make.height.equalTo(50)
        }
    }
    
    // MARK: - Input Events

    @objc private func usernameChanged() {
        usernameSubject.send(usernameField.text ?? "")
    }

    @objc private func passwordChanged() {
        passwordSubject.send(passwordField.text ?? "")
    }
    
    // MARK: - Combine Binding
    
    private func bindInputs() {
        // 两个输入框任意一个发生变化，
        // combineLatest 都会拿到两者最新的值
        Publishers.CombineLatest(usernameSubject, passwordSubject)
            .map { username, password -> Bool in
                let validUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
                let validPassword = password.count >= 6
                return validUsername && validPassword
            }
            .removeDuplicates() // 仅在合法性结果发生变化时更新 UI
            .receive(on: DispatchQueue.main)  // 在主线程处理
            .sink { [weak self] isValid in  // ⚠️ 注意 weak self
                guard let self else { return }
                debugPrint("收到了数据流 isValid = ", isValid)
                self.loginButton.isEnabled = isValid
                self.loginButton.alpha = isValid ? 1 : 0.5
            }.store(in: &cancellables)
    }
}
```

### 这个例子最重要的 API：combineLatest

```swift
Publishers.CombineLatest(
    usernameSubject,
    passwordSubject
)
```

它的行为是：

- 两个 Publisher 都至少发送过一个值后，才可以输出组合结果。
- 任意一个 Publisher 发生变化，使用它的新值与另一个 Publisher 的最新值组合。
- 两个 CurrentValueSubject 自带初始值，因此订阅后立即可以计算一次登录按钮状态。

## 4.Combine 网络请求与异步操作

### 4.1 URLSession + Combine

以前可能这样写：

```swift
URLSession.shared.dataTask(with: url) { data, response, error in
    // 判断错误
    // 解析 JSON
    // 切换主线程
    // 更新 UI
}.resume()
```

Combine 把网络请求转变成 `Publisher`。

下面通过 `JSONPlaceholder` 的公开示例接口演示获取一条文章数据。

```swift
import Foundation
import Combine

struct Post: Decodable {
    let userId: Int
    let id: Int
    let title: String
    let body: String
}

enum APIError: Error {
    case invalidResponse
    case invalidStatusCode(Int)
}

final class PostService {

    func fetchPost(id: Int) -> AnyPublisher<Post, Error> {

        let url = URL(
            string: "https://jsonplaceholder.typicode.com/posts/\(id)"
        )!

        return URLSession.shared
            // 创建网络 Publisher
            .dataTaskPublisher(for: url)

            // 校验 HTTP 响应
            .tryMap { data, response -> Data in
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                guard (200...299).contains(http.statusCode) else {
                    throw APIError.invalidStatusCode(http.statusCode)
                }

                return data
            }

            // 将 JSON 解码为 Post
            .decode(type: Post.self, decoder: JSONDecoder())

            // 隐藏复杂的上游 Publisher 类型
            .eraseToAnyPublisher()
    }
}
```

**在 UIKit `ViewController` 中订阅**
```swift
private let service = PostService()
private var cancellables = Set<AnyCancellable>()

private func loadPost() {
    service.fetchPost(id: 1)

        // URLSession 的结果不保证在主线程
        .receive(on: DispatchQueue.main)

        .sink(
            receiveCompletion: { completion in

                switch completion {
                case .finished:
                    print("请求完成")

                case .failure(let error):
                    print("请求失败：\(error)")
                }

            },
            receiveValue: { [weak self] post in

                // 这里已经切到主线程
                self?.titleLabel.text = post.title
                self?.bodyLabel.text = post.body
            }
        )
        .store(in: &cancellables)
}
```

这里的流程是：

```
URLSession
    ↓
Data + URLResponse
    ↓ tryMap
校验 HTTP 状态码
    ↓ decode
Post Model
    ↓ receive(on: main)
主线程
    ↓ sink
更新 UILabel
```

### 4.2 receive(on:) 与 subscribe(on:) 的区别

#### receive(on:)

控制下游接收值和完成事件的调度环境。

```swift
publisher
    .receive(on: DispatchQueue.main)
    .sink { value in
        // 下游在主队列接收
    }
```

#### subscribe(on:)

影响上游的订阅、请求 Demand、取消等操作的调度环境。

```swift
publisher
    .subscribe(on: DispatchQueue.global(qos: .userInitiated))
    .receive(on: DispatchQueue.main)
    .sink { value in
        // UI 更新
    }
```

注意，`subscribe(on:)` 不是一个可以保证「整个网络请求都在这条队列执行」的开关，也不代表它后面的所有 Operator 都自动在后台运行。

### 4.3 debounce 和 throttle 的区别











































































