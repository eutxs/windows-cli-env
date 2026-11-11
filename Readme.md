# windows-cli-env

> **For DeepSeek Harness only.** 这个 skill 假定宿主是 DSH：靠 `skill` 工具的 `resourceBase=directory` 加载 `references/`，靠 `ask_user_question` 弹窗逐项询问。换别的 agent 宿主，这两处的调用方式要自己改。

## 🚀 如何安装

这是一个纯文本的 Agent Skill。不需要任何安装程序，AI 自己就能装。

**方式一：一句话让 AI 装（推荐）**
在 dsh 会话中直接发送：
> "帮我安装这个 skill：https://github.com/eutxs/windows-cli-env/archive/refs/heads/main.zip ，下载解压到 ~/.dsh/skills/windows-cli-env"

**方式二：手动下载**
1. 下载本仓库的 ZIP 压缩包。
2. 解压出 `windows-cli-env` 文件夹，整个丢进 `C:\Users\<你的用户名>\.dsh\skills\` 目录。
3. 重启 dsh。

**方式三：直接注入**
把本仓库的 `SKILL.md` 复制给 AI，告诉它：“按这个 SOP 帮我配环境。”