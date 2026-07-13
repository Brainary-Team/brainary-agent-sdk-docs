# brainary-agent-sdk-docs

Brainary（领智智能）**官网** 与 **brainary-agent-sdk 文档站** 的源码与部署。纯静态、无 CDN 外链，自动部署到 GitHub Pages。

- **官网**（`website/`）：Vite + Tailwind 的产品落地页，站点根 `/`。
- **SDK 文档**（`user_docs/`）：基于 [VitePress](https://vitepress.dev/) 的中文文档站，挂在 `<base>docs/`。以 **Rust 版 brainary-agent-sdk**（`/sdk/**`）为主，**Python 版**（`/sdk-py/**`）作为跨语言对齐蓝本。

在线地址：`https://zibuyu2015831.github.io/brainary-agent-sdk-docs/`

## 本地开发

```bash
# 官网 + 文档一键起（单源代理，官网在 /、文档在 /docs/）
./start-docs.sh

# 或分别：
cd website   && pnpm install && pnpm dev        # 官网 :5174
cd user_docs && pnpm install && pnpm docs:dev   # 文档 :5173
```

## 构建

```bash
./build.sh            # 组装 dist/（官网 + 全部冻结文档版本 + 运行时重定向）
./build.sh --serve    # 组装并在 SITE_BASE 子路径下本地预览
```

`dist/` 自包含、可直接放到任意静态服务器（或由 CI 部署到 Pages）。

## 版本切换（Python 式发版冻结）

文档站支持按版本切换整套文档（类似 Python 官方文档顶栏的版本下拉框）。核心模型：

- **版本号 = brainary-agent-sdk 源码提交短 hash（预 tag 阶段）**：SDK 尚无正式 tag，故版本号直接取所关联源码提交的短 hash，可溯源；下拉标签形如 `rs@3caa334 · 2026-07-10 (latest)`。正式 tag 后用 `--version` 传 semver（如 `1.0`）即可无缝切换。
- **真冻结**：每个版本是一次独立静态构建，产物存进 `user_docs/.versions/<ver>/` 并提交进 git，此后永不重建。
- **运行时版本发现**：顶栏下拉框运行时拉取 `user_docs/public/versions.json`（唯一可变清单）；版本段识别是**清单驱动**的，与命名格式解耦，hash / semver 通吃。

### 发版（一键）

```bash
git -C ../brainary-rs fetch     # 先拉最新，确保关联的源码主干是最新提交
./release.sh                    # 冻结当前源码主干 → 短 hash 版本 → commit → push
```

`release.sh` = `snapshot.sh`（冻结）+ `git add/commit/push`。推送到 `main` 后 CI 自动构建并部署。参数透传给 `snapshot.sh`：

- `./release.sh` —— 取源码 `origin/master` 最新提交冻结。
- `./release.sh --ref <分支/tag/commit>` —— 冻结指定 ref。
- `./release.sh --version 1.0` —— 正式 semver 版本。
- 环境变量 `BRAINARY_RS_DIR` 指定源码仓路径（默认 `../brainary-rs`）；`RS_REF` 覆盖 ref（默认 `origin/master`）。

> 预 tag 阶段的 hash 快照并非真实发布，可按需只保留最新一两个（`git rm -r user_docs/.versions/<旧hash>` 后重跑），避免产物无限堆进 git。

## 部署（GitHub Pages）

CI（`.github/workflows/deploy.yml`）在 push `main` 或手动 dispatch 时跑 `./build.sh` 组装 `dist/` 并部署到 Pages。冻结版本已在 git，CI 很轻量。

**首次启用（一次性）**：Settings → Pages → Source 选 **GitHub Actions**。

**部署地址与 `SITE_BASE`**：项目页挂在子路径，故全站绝对路径前缀由单一开关 `deploy.env` 的 `SITE_BASE`（默认 `/brainary-agent-sdk-docs/`）驱动，`snapshot.sh`（冻结时烤进产物）与 `build.sh`（生成重定向）共读。官网文档链接用相对路径、切换器的文档根经 `__DOCS_ROOT__` 编译期注入，故根/子路径都自适应。

> ⚠ `SITE_BASE` 会被烤进冻结产物：改了它必须重新冻结当前版本。

**切换自定义域名（根路径）**：① `deploy.env` 改 `SITE_BASE=/`；② 仓库根放 `CNAME`（`build.sh` 会拷进 `dist/`）；③ `git rm -r user_docs/.versions/<当前版本>` 后 `./release.sh` 重冻；④ GitHub 配域名 + DNS。

## 作者纪律（改文档前必读）

- markdown 内部链接一律写**根绝对且不含版本**（`/sdk/…`、`/sdk-py/…`），**绝不**写死 `/docs/…`。VitePress 构建时按 `base` 自动加前缀，故切版本 / 换部署基路径都无需改链接。守卫：`grep -rn '](/docs/' user_docs/sdk user_docs/sdk-py` 应为空。
- 版本清单必须放 `user_docs/public/versions.json`（VitePress 把 `public/` 挂到 base 根，dev 与 build 都可达）。
