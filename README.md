# hayamiz-agentkit

[早水](https://github.com/hayamiz) がコーディングエージェント (主に
[Claude Code](https://claude.com/claude-code)) 向けに使っているスキル・プラグイン集です。
[APM](https://github.com/apm-pkg/apm) 経由で配布します。

## 構成

```
skills/     スキル (1 ディレクトリ 1 スキル、各 SKILL.md を持つ)
  commit-all/      worktree のすべての差分をセマンティックにまとめて commit
  commit-session/  現セッションで変更したファイルだけを commit
plugins/    Claude Code プラグイン (1 ディレクトリ 1 プラグイン)
  gardener/  リポジトリ健全性の監査 — docs sync / best-practices チェック等
  ticket/    ファイルベースのチケット運用 (init / create / check / triage / fix)
```

各プラグイン・スキルの詳細は、それぞれの `SKILL.md` / `plugin.json` を参照してください。

## インストール

前提: [`apm`](https://github.com/apm-pkg/apm) CLI が入っていること。

プロジェクトに個別で入れる場合:

```sh
# スキル
apm install hayamiz/hayamiz-agentkit/skills/commit-all
apm install hayamiz/hayamiz-agentkit/skills/commit-session

# プラグイン
apm install hayamiz/hayamiz-agentkit/plugins/gardener
apm install hayamiz/hayamiz-agentkit/plugins/ticket
```

ユーザーグローバル (`~/.apm/`) に入れるときは `-g` を付けます:

```sh
apm install -g hayamiz/hayamiz-agentkit/plugins/gardener
```

このリポジトリ自身の `apm.yml` で管理されている依存をまとめて入れ直すには:

```sh
apm install
```

## 開発時のメモ

- `.claude/skills/` は `apm install` が生成するため gitignore 済みです。ソースを編集するときは
  `skills/<name>/` または `plugins/<name>/skills/<name>/` を触ってください。
- 新しいスキル / プラグインを追加したら `apm.yml` の `dependencies.apm` にも
  エントリを足し、`apm install` でロックファイルを更新します。
- 詳しい規約は [`CLAUDE.md`](CLAUDE.md)、[`skills/CLAUDE.md`](skills/CLAUDE.md)、
  [`plugins/CLAUDE.md`](plugins/CLAUDE.md) を参照してください。
