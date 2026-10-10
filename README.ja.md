Language: [English](README.md) | 日本語

# skill-stocktake

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/shimo4228/skill-stocktake)

`~/.claude/skills/`（と今いるプロジェクトの `.claude/skills/`）に入っている Claude Code のスキルを監査し、スキルごとに Keep / Improve / Update / Retire / Merge などの判定（全種類は[判定基準](#判定基準)にあります）を提案する [Agent Skill](https://agentskills.io/specification)（英語）です。まずコードでスキルの構造を機械的に検査し（スキルが名指しするスクリプト・ファイル・パスが実在するかを確かめます）、次に少数ずつのまとまりに分けて毎回まっさらなコンテキストで 1 件ずつ精査し、最後に専任のエージェントがスキル同士の重複を調べます。判定は数値スコアでなく、証拠を総合して出します。どのスキルも、あなたが確認するまで削除・併合・改善への引き渡しはされません。プラグインで入れたスキルは検査の対象外です。実行の最後には、スキルごとに 1 行の表が出ます。各行の理由はそれだけで判断できるように書かれ、たとえば Merge の理由は "42-line thin content; Step 4 of chatlog-to-article already covers this workflow. Integrate the 'article angle' tip there as a note." のようになります。

監査は、スキルが名指しする URL をあなたのマシンから 1 回ずつ確認し、コストの報告のために別の `claude -p` セッションを 1 つ起動します。このセッションと、スキルを精査する並列のサブエージェントは、あなたの Claude の利用枠を使います。著者のほかの仕事は [著者のほかの仕事](#著者のほかの仕事) にまとめています。

## インストール

skill-stocktake は [skill-health](https://github.com/shimo4228/skill-health)（英語）のスクリプト（構造スキャンと URL の確認）を実行し、skill-health はこのスキルの使用回数スクリプトを実行します。そのため 2 つは一緒にインストールしてください。どちらもスクリプトを [`uv`](https://docs.astral.sh/uv/)（英語）と Python 3.11 以上で実行します。

経路は 2 つあります。clone（1 つ目のブロック）はこの 2 つだけを入れます。akc-cycle プラグイン（2 つ目のブロック）は 2 つに加えて、監査が Improve と Update の判定を引き渡す `skill-creator` も入れます。

```bash
git clone https://github.com/shimo4228/skill-stocktake
git clone https://github.com/shimo4228/skill-health
mkdir -p ~/.claude/skills
cp -r skill-stocktake/skills/skill-stocktake skill-health/skills/skill-health ~/.claude/skills/
```

clone で入れた場合、スキルは `~/.claude/skills/skill-stocktake` と `~/.claude/skills/skill-health` にあるスクリプトを呼ぶので、フォルダはその場所に置いてください。あとは「スキルを棚卸しして」のように頼むか、`/skill-stocktake` と入力します。

同じスキルは、Agent Knowledge Cycle（AKC: コーディングエージェントが繰り返した経験をスキルとルールに変える、人が承認する著者の 6 フェーズのサイクル）のほかのスキルと一緒に、Claude Code プラグイン [akc-cycle](https://github.com/shimo4228/akc-cycle)（英語）にも入っています。skill-stocktake はこのサイクルの Curate（整理）フェーズに属し、プラグインでは `/akc-cycle:skill-stocktake` という名前で呼びます。このリポジトリは同じ元から一方向に同期しているので、同期と同期の間はプラグインより古いことがあります。

```
/plugin marketplace add shimo4228/akc-cycle
/plugin install akc-cycle@akc-cycle
```

## 要件

- **Glob**・**Read**・**Write**・**Bash**・**サブエージェント（Task/Agent）** ツールを使える Claude Code（スキルごとの精査のバッチと重複と矛盾のプローブは並列サブエージェントで実行します。[仕組み](#仕組み)の Phase 2 と Phase 3 です）。
- `uv` と Python 3.11 以上、そしてこのスキルの隣にインストールした skill-health（「インストール」参照）。
- `changed` モード用の `jq`（前回実行時とのファイル時刻の比較に使います）。
- `ctx` 列（各スキルの一覧行が毎ターン足すトークン数）には、`/skill-doctor` の報告を出す Claude Code 2.1.269 以上が必要です（2026-09-15 時点）。報告が得られないとき、この列は `—`（未計測）になります。
- 使用回数列（直近 14 日の意図的な使用回数と最終使用日）には、`~/.claude/metrics/skill-usage.jsonl` のログを使います。このログを書くはずのリポジトリ内の hook `hooks/log-skill-usage.sh` は、読み込む補助ファイル `hooks/_session-common.sh` が含まれていないため、まだ動きません。ログが無くても監査は動作し、この列は 0 ではなく `—`（未計測）になります。

## モード

| モード | トリガー | 動作 |
|--------|----------|------|
| **full** | デフォルト、または `/skill-stocktake full` | 全スキルを読み込んで評価 |
| **changed** | `/skill-stocktake changed` | 前回以降に `SKILL.md` が変更されたスキルのみ再評価。残りは判定台帳（各回の判定を記録するファイル `results.json`）から引き継ぐ。構造の事前検査と重複と矛盾のプローブ（[仕組み](#仕組み)の Phase 0 と Phase 3）は全スキルに対して実行 |

## 仕組み

1. **Phase 0 — 構造の事前検査（コードによる）**: [skill-health](https://github.com/shimo4228/skill-health) のスキャナで、存在しないファイルやスクリプトを指している箇所を見つけ、判定台帳のキーがスキルのフォルダ名と一致し、そのパスが実在することを確かめます。台帳に記録されたスキルのフォルダが実在しない場合、そのエントリは内容の判断まで進まず、台帳から削除されてレポートに記載されます。存在しないファイルを指す箇所があるスキルは、そのまま内容の判断に進みます。フォルダが他人のツリーへの symlink になっているスキルは `Out of scope` とし、欠陥があれば編集せず上流に報告します。
2. **Phase 1 — インベントリ**: `~/.claude/skills/*/SKILL.md`（および `$PWD/.claude/skills/` があればプロジェクトスキル）を Glob で列挙します。続いて親セッションが 3 種類の証拠を 1 回だけ集めます: 同梱スクリプトによる使用回数（使用ログが無い間は `—` になります。[要件](#要件)参照）、スキルが名指しする全 URL の live / dead / blocked（skill-health 経由で直列に確認）、そして `claude -p "/skill-doctor"` による、各スキルの一覧行が毎ターン足すトークン数です。
3. **Phase 2 — スキルごとの精査（小バッチ並列）**: 10–12 件ずつに分割し、バッチごとに 1 サブエージェントを新しいコンテキストで起動します。Stage 1 では、スキルごとに実用性・スコープ整合・バッチ内重複・鮮度・本文の肥大（些末な禁止の列挙、繰り返しの強調、原則にまとめられる手順の羅列が無いか）・description に紛れた指示文を Yes/No で問い、名指しされたパスと CLI フラグは**無条件に**実在を確かめます。さらに全スキルが 2 つの存在の問いに答えます: ほかの何も担っていない仕事がこのスキルの消失で失われるか、選択・ドリフト・保守のコストに見合うか。Stage 2 では、非 Keep の暫定判定ごとに、そのスキルに合わせた反証の問いを立てます。Yes/No の答えは総合判定の証拠であり、スコアに集約しません。バッチエージェントには過去の判定も使用回数とコストのデータも渡しません。
4. **Phase 3 — 重複と矛盾のプローブ（専任エージェント）**: 1 エージェントが全スキルの name + description を走査して候補クラスタを貪欲に列挙し、候補の本文を並べて読み、各候補が同じ仕事を二重に持つ重複なのか、別の資産が仕事全体をすでに担っているのか、役割の分担がスキルに書かれているのか、隣り合うが別の仕事なのか、矛盾しているのか（同時に読み込まれうる 2 つのスキルが同じ場面で逆の指示を出す）を判定します。Merge 判定を出すのは、同じ仕事を二重に持っていて、併合先へ移す内容を具体的に挙げられるときだけです。仕事全体がすでに担われていて移すものが残っていないスキルは Retire になります。
5. **Phase 4 — 集約**: 親がバッチ判定・プローブの判定・使用回数・コストを集約し、自己完結した理由付きのスキルごとの表（`Skill | ctx | 14d | last used | Verdict | Reason`）を出力します。判定を決めるのは内容で、使用回数は参考の証拠であり、閾値にも拒否権にもなりません。
6. **Phase 5 — 確認と実行**: 非 Keep 候補は **1 件ずつ**確認します。証拠を提示してから `[y/n/skip]` を聞き、一括承認はしません。Retire/Merge はそのファイルの確認後にのみ実行します。Improve/Update はスキルごとに、改善の作業を担う `skill-creator` という名前のスキルへ引き渡すかを尋ねます（著者の [`skill-creator`](https://github.com/shimo4228/akc-cycle/tree/main/skills/skill-creator)（英語）は akc-cycle プラグインに入っています）。判定台帳はその場で更新します。

## 判定基準

| 判定 | 意味 |
|------|------|
| **Keep** | 有用かつ最新で、固有の価値がある |
| **Improve** | 維持する価値はあるが、具体的な改善が必要 |
| **Update** | 参照している技術やファイルが古くなっている（証拠付きで検証済み） |
| **Retire** | 陳腐化している、コストに見合わない、または別の資産が全体を担っていて移すものが残っていない |
| **Merge into [X]** | 他のスキルと同じ仕事を二重に持ち、併合先へ移す内容を具体的に挙げられる。併合先と移す内容を名指しする |
| **Retire-and-absorb** | 従うはずのスキルと矛盾し、単独では発火しない。削除前に移すべき内容を名指しする |
| **Out of scope** | 他人のツリーが持つスキル（symlink のフォルダ）。欠陥は上流へ |

## 参考研究

監査は **集合コスト (aggregate cost)**（個々のスキルを超えた、ライブラリ全体のコスト）という観点で評価します。大きく未整理なスキルライブラリはエージェントのスキル選択を劣化させ、挙動をスキルが無いときの水準へ引き戻すので、ライブラリが大きいほど Keep と判定する基準を厳しくする、という考え方です。2026 年のエージェントスキルライブラリに関する経験的研究に基づいています（いずれも英語）:

- [How Well Do Agentic Skills Work in the Wild](https://arxiv.org/abs/2604.04323) (Liu et al., 2026): 現実的な設定では、大きく未整理なライブラリから検索するほどスキルの利得が弱まると報告しています。
- [SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks](https://arxiv.org/abs/2602.12670) (Li et al., 2026): キュレーションはドメイン横断で大きく不均一な利得を生み、スキルの品質は結果に非線形に効くと報告しています。
- [SkillOps: Managing LLM Agent Skill Libraries as Self-Maintaining Software Ecosystems](https://arxiv.org/abs/2605.13716) (Pu, Song & Zhao, 2026): 「スキル技術的負債」という見方を示し、ライブラリを健全に保つ作業をそれ自体ひとつの分野として扱っています。

SkillOps がライブラリの保守を自己維持するエコシステムとして捉えるのに対し、skill-stocktake は**何を残すかの判断**を人間が持ち続けます。監査は判定を提案し、確定はあなたが行います。

## 著者のほかの仕事

- **[AI の苦手な仕事をスクリプトに逃がす — スキル棚卸しコマンドの設計・実装・公開の全記録](https://zenn.dev/shimo4228/articles/skill-stocktake-design-journey)**（[English](https://dev.to/shimo4228/offloading-ais-weak-spots-to-shell-scripts-designing-building-and-publishing-a-skill-audit-2ll8)）: モデルが実行のたびに結果を変えたため、この監査の初期版がファイル一覧とタイムスタンプをモデルから決定論的なコードへ移した経緯です。
- **[LLM-as-judge はスコアを集計しない — チェックは証拠、判定は総合判断](https://zenn.dev/shimo4228/articles/llm-judge-checks-not-scores)**（[English](https://dev.to/shimo4228/llm-as-judge-shouldnt-aggregate-scores-binary-checks-as-evidence-one-holistic-verdict-822)）: 監査が Yes/No の問いを 1 つの名前付き判定の証拠として扱う理由と、小バッチ方式に切り替えるきっかけになった 73 スキルの再監査です。
- **[akc-cycle](https://github.com/shimo4228/akc-cycle)**: このスキルをサイクルのほかのスキルと一緒に、1 つの Claude Code プラグインとして入れます（英語）。
- **[Agent Knowledge Cycle](https://github.com/shimo4228/agent-knowledge-cycle)**: Curate を含むサイクルの各フェーズがなぜあるのかを、日付付きの設計判断として記録しています。
- **[skill-health](https://github.com/shimo4228/skill-health)**: この監査が最初に実行する決定論的なスキャンで、存在しないスクリプト・ファイル・兄弟スキルを名指しするスキルを見つけます。一緒にインストールしてください（英語）。
- **[rules-stocktake](https://github.com/shimo4228/rules-stocktake)**: 常駐ルールについての同種の監査で、各ルールが毎セッション払わせるコストを量ります。
- **[agent-stocktake](https://github.com/shimo4228/agent-stocktake)**: サブエージェント定義についての同種の監査です。description は毎セッション常駐し、本文は呼ばれたときだけ読み込まれます。
- **[shimo4228](https://github.com/shimo4228/shimo4228)**: 著者の拠点リポジトリです。AKC をほかの長期プロジェクトとその DOI と並べています。

## ライセンス

MIT

<details>
<summary>ツールと AI アシスタント向けの資料</summary>

skill-stocktake は、`~/.claude/skills/` と今いるプロジェクトの `.claude/skills/` にあるスキル（プラグインで入れたスキルは対象外）を監査してスキルごとに判定を 1 つ提案する Claude Code 向けの Agent Skill です。手で見直せる量を超えてスキルが増え、古い・壊れた・重複した・矛盾したスキルを証拠付きで見つけたい人のためのものです。判定は Keep・Improve・Update・Retire・Merge into [X]・Retire-and-absorb で、他人のツリーから symlink されたスキルには Out of scope を付けます。1 件ずつの確認なしにスキルファイルを削除・併合・編集することはありません。判定台帳は毎回書き込みます。

存在する理由は 2 つあります。大きく未整理なスキルライブラリはスキル選択を劣化させること、そして 1 つのコンテキストでは全件をうまく監査できないことです。著者の 73 スキルのライブラリで、全スキルを 1 つのコンテキストに読み込む旧版は全件 Keep を返しました。同じライブラリで、毎回まっさらなコンテキストで動く小バッチは 12 件の非 Keep（半数は決定論的証拠付き）を検出し、専任の重複プローブは全本文を 1 つのコンテキストに入れずにライブラリ全体を見渡す視点を保ちました。そのため監査は、チェックする性質で仕事を分けます: 実在と参照はコード、スキルごとの品質は少数ずつのまっさらなコンテキスト、ライブラリ横断の重複と矛盾は 1 エージェントです。

基本的な事実: MIT ライセンス。`SKILL.md` と Python スクリプト 1 本 `skills/skill-stocktake/scripts/usage_stats.py`（Python 3.11 以上、標準ライブラリのみ、同梱の `uv.lock` で `uv` から実行、テストは `skills/skill-stocktake/tests/`）、任意の Claude Code 用使用計測 hook `hooks/log-skill-usage.sh`（bash と `jq`、bats テストは `tests/log-skill-usage.bats`）からなります。この hook は、読み込む補助ファイル `hooks/_session-common.sh` がリポジトリに無いため、まだ動きません（Skill tool の呼び出しを `invoke`、タイプされた `/skill` の起動を `slash`、スキル `.md` の Read を `read` として記録し、意図的な使用として数えるのは `invoke` と `slash` だけです）。著者 1 人（@shimo4228）が保守しています。状態: 稼働中で、著者の Claude Code ハーネスから `scripts/sync-from-local.sh`（commit はしません）で一方向に同期しており、akc-cycle プラグインにも `/akc-cycle:skill-stocktake` として入っているため、同期と同期の間はこのリポジトリがプラグインより古いことがあります。要件: Glob・Read・Write・Bash・サブエージェントを使える Claude Code、`uv`、`~/.claude/skills/skill-health` にインストールした skill-health（2 つは互いのスクリプトを実行します）、`changed` モード用の `jq`。有料の鍵は不要ですが、並列サブエージェントと 1 回の `claude -p "/skill-doctor"` セッションは利用者の Claude の利用枠を使い、スキルが名指しする URL は 1 回ずつ直列に取得されます。台帳を `~/.claude/skills/skill-stocktake/results.json` に置き、スキルファイルの削除や編集は 1 件ごとの確認の後だけ行い、Improve と Update の判定は `skill-creator` という名前のスキルに引き渡します。

例: full の実行はまず、走査したパス、見つかったスキル数、使用回数と一覧行のトークン数（`ctx`）が計測できたかを述べます。続いて `Skill | ctx | 14d | last used | Verdict | Reason` の表を出力します。`ctx` はスキルの一覧行が毎ターン足すトークン数、`14d` は直近 14 日の意図的な使用回数（タイプされたもの、またはモデルが呼んだもの）です。Merge の理由は例えば "42-line thin content; Step 4 of chatlog-to-article already covers this workflow. Integrate the 'article angle' tip there as a note." のように書かれます。その後、非 Keep の判定を 1 件ずつ証拠と `[y/n/skip]` で確認します。

リンク: [skills/skill-stocktake/SKILL.md](skills/skill-stocktake/SKILL.md)（英語）がスキル本体、[llms.txt](llms.txt) と [llms-full.txt](llms-full.txt)（英語）が機械可読の要約と参照資料です。このスキルは [Agent Knowledge Cycle (AKC)](https://github.com/shimo4228/agent-knowledge-cycle) の Curate フェーズの一部を実装しています。AKC の concept DOI（常に最新版へつながる代表 DOI）は [10.5281/zenodo.19200726](https://doi.org/10.5281/zenodo.19200726) で、引用はこの DOI で行ってください。サイクル全体をインストールできる形は [akc-cycle](https://github.com/shimo4228/akc-cycle)（英語）です。

</details>
