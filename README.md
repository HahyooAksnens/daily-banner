# 每日一句 · Daily Banner

一个简洁的 macOS 半透明桌面文字横幅，用来给自己留一句话。

横幅位于桌面层，普通应用窗口会盖住它。鼠标进入横幅时显示编辑栏，移开后隐藏。

## 功能

- 直接编辑文字，支持多行。
- 字体、字号、颜色、加粗。
- 居中／左对齐，额外行间距 0–48 点。
- 拖动移动，右下角拖动缩放。
- 文字、样式、位置和大小自动保存到本机。
- 菜单栏显示／隐藏及退出。

无联网功能。个人文字及本机设置不会随源码上传。

## 构建与运行

需要 macOS 和 Apple Command Line Tools（Swift / AppKit）。当前构建在 Apple Silicon Mac 上验证。

```sh
git clone https://github.com/HahyooAksnens/daily-banner.git
cd daily-banner
zsh build.sh
open 每日一句.app
```

如果尚未安装命令行开发工具，先运行 `xcode-select --install`，按系统提示完成安装。

构建会生成本地签名的应用，不依赖第三方包。仓库只保存源码和应用元数据，不包含预编译程序。

## 使用

点击文字直接输入。编辑栏里的居中按钮亮起表示居中，关闭后左对齐；「行距」对多行文字生效。拖动左上角手柄可移动横幅，拖动右下角可调整大小。

更多操作见 [使用说明](使用说明.txt)。

## 验证

在有图形桌面会话的 Mac 上运行：

```sh
每日一句.app/Contents/MacOS/DailyBanner --smoke-test
```

自检使用独立的临时偏好设置，覆盖旧数据兼容、对齐、行间距、颜色、保存、悬停显隐和桌面层级。

源码入口：[Sources/main.swift](Sources/main.swift)。
