---
layout: home

hero:
  name: "brainary-agent-sdk"
  text: "构建 LLM Agent 的门面 SDK"
  tagline: query() 一行式入口与 BrainaryClient 多轮，统一 Options 与步级 Message 流，构建具备执行、记忆与工具调用的智能体；Python 与 Rust 双版本对齐同一套接口。
  actions:
    - theme: brand
      text: Python 版能力总览
      link: /sdk-py/overview
    - theme: alt
      text: Rust 版能力总览
      link: /sdk/overview

features:
  - title: 两个入口：query 与 Client
    details: query() 一行式跑一次性任务，BrainaryClient 承载多轮会话；同一套 Options 塑形、同一条步级 Message 流，应用开发者默认只依赖 SDK 一行。
  - title: 内置工具与自定义工具
    details: 开箱即用的内置工具目录，配合 FunctionTools 自定义扩展；错误处理、中断与护栏、会话导出等能力统一经 SDK 表面暴露。
  - title: Python 与 Rust 双版本
    details: brainary-agent-sdk（Python）与 brainary-agent-sdk（Rust）提供对齐的接口形态与消息模型，按你的技术栈择一接入。
---

> 🚧 标注 🚧 的页面或小节仍在完善，🟠 表示能力尚在规范/占位阶段，🔴 表示能力暂不可用。
