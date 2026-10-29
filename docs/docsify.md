本文档是使用 [docsify](https://docsify.js.org/) 生成的，文档内容是我在学习 `flutter` 开发的过程中，记录一下学习过程中的一些知识。


- `docsify`官网: https://docsify.js.org/
- `docsify`是一个基于 javascript 的文档生成工具，它可以将 `markdown` 文件转换为一个静态的网站。


使用 `docsify` 需要安装 `node.js` 和 `npm`。
- 安装 `node.js` 和 `npm` 可以参考 [node.js 官网](https://nodejs.org/en/download)。
- 推荐使用`brew`安装 `node.js`，执行命令的过程中，注意查看输出，会有提示环境变量添加到 `.zshrc` 中的命令。


```sh
# 初始化 docsify 项目
$ docsify init ./docs

# 启动 docsify 项目
$ docsify serve docs
```


在 `GitHub Pages` 中部署 `docsify` 项目:
- 在 `docsify`的官网中，有详细的部署说明。
- 部署过程中，需要注意的是，`docsify` 项目的根目录需要是 `docs` 目录。
- 还需要有`.nojekyll`文件，用于告诉 `GitHub Pages` 不要使用 `Jekyll` 来构建项目。


一个在线提供图片URL的网站：
- `https://lorempics.com/`

