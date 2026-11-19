# Claude Desktop usage

Claude Code totals combine CLI sessions with usage-bearing local Claude Desktop
Chat and Cowork records. Both `~/Library/Application Support/Claude` and
`~/Library/Application Support/Claude-3p` are scanned.

Supported sources:

- `local-agent-mode-sessions/**/audit.jsonl` for Chat and Cowork. SDK result totals
  replace streamed snapshots; each initialization starts a new ledger.
- Embedded `.claude/projects/**/*.jsonl` when the audit log cannot supply usage.
- `local-agent-mode-sessions/<account>/<org>/usage-ledger/YYYY-MM-DD[.N].ndjson`
  for Chat calls, including records retained after a conversation is deleted.
  Ledger rows are deltas. Code and Cowork ledger rows are already covered by
  their transcript sources and are not added again.

Chat session metadata maps CLI transcript IDs to stable Desktop IDs for deduplication.
When both an audit log and Chat ledger describe the same session, the audit log
is used. Repeated scans replace that session's cached usage records.

Coverage depends on the files present on the device. In particular, a standard
Claude subscription Chat cache may contain UI state and model limits without
actual input/output token counters. Such history is not treated as zero usage
or estimated from message length; it cannot be included in token totals from
local files. Cloud history is not downloaded by the scanner.
