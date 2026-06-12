---
name: <feature-slug>
version: v0.1.0-spec
status: DRAFT
date: <YYYY-MM-DD>
authors: <user> + Claude
template_version: 1
---

# Spec: <feature title>

> One-sentence summary.

## 0. 目录 (TOC)

- [1. 目标定位](#1-目标定位)
- [2. 范围边界](#2-范围边界)
- [3. 架构数据流](#3-架构数据流)
- [4. 模块边界](#4-模块边界)
- [5. API 契约](#5-api-契约)
- [6. 扩展点 / 插件接口](#6-扩展点--插件接口)
- [7. 错误 + 边界 case](#7-错误--边界-case)
- [8. 成本契约](#8-成本契约)
- [9. 测试矩阵](#9-测试矩阵)
- [10. 向后兼容](#10-向后兼容)
- [11. 风险登记](#11-风险登记)

## 1. 目标定位

- 解决什么用户痛点
- 与产品 positioning 对齐
- 与全局 CLAUDE.md 哪些规则对齐(列映射表)

## 2. 范围边界

- v<X>.<Y>.<Z> 做
- v<X>.<Y>.<Z> 不做(写死)
- 推迟到 v.next

## 3. 架构数据流

- input → processing → output
- ASCII 数据流图
- DB tables / cache layers / 状态机

## 4. 模块边界

- crate / module / file 边界
- 跨仓边界

## 5. API 契约

- REST endpoints / WS / CLI / typed schema
- input/output 字段 + 错误码

## 6. 扩展点 / 插件接口

- 怎么加新 source / agent / backend
- 配置覆盖位置

## 7. 错误 + 边界 case

- 错误码 (kebab-case)
- 边界 case 矩阵
- graceful degradation

## 8. 成本契约

- 磁盘开销
- LLM token 估算
- 时间金钱归属
- 本地算力

## 9. 测试矩阵

- 6 类下限 (per §6.1)
- 通过判据
- multi-seed (per §2.3)

## 10. 向后兼容

- SemVer 策略
- schema versioning
- 老 client 行为
- migration path

## 11. 风险登记

| # | 风险 | 概率 | 影响 | 缓解 |
|---|------|------|------|------|
| R1 | ... | High/Med/Low | High/Med/Low | ... |

## Appendix

<Per-feature appendices>
