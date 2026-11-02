# 贡献指南

欢迎提交 Issue 和 Pull Request。

## 提交问题

请附上：

- Windows、WSL 发行版及 `usbipd --version` 的版本
- `usbipd list` 的相关行
- `%LOCALAPPDATA%\usbipd-wsl-auto\attach.log` 的相关日志
- 复现步骤和预期行为

请先删除用户名、路径中的个人信息、设备序列号等不需要公开的内容。

## 修改代码

- 保持 Windows PowerShell 5.1 兼容，不使用 PowerShell 7 专有语法。
- 含中文的 `.ps1` 文件必须保存为 **带 BOM 的 UTF-8**，否则 Windows PowerShell 5.1 可能按系统 ANSI 编码误读。
- 不提交 `config.json`、日志、设备状态或本机排查文件。
- 默认白名单只放专用 USB 串口。整只复合设备转发可能同时移除 Windows 的 JTAG、存储或其他接口，不应无提示加入。
- 不使用 `usbipd policy remove --all`，不主动 detach 用户已经挂进 WSL 的设备。

## 验证

至少对所有 `.ps1` 做 PowerShell 语法解析检查。涉及挂载行为时，请在实际 Windows + WSL2 环境验证安装、重复安装、拔插恢复和卸载，并在 Pull Request 中说明测试范围和结果。

## 许可证

贡献代码默认按照本仓库的 [MIT License](LICENSE) 发布。
