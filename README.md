# dot-bridge

Let your ChatGPT dot use your Mac without the ChatGPT desktop app.

dot-bridge is a small Node program. It runs an MCP server on your Mac, opens a Cloudflare tunnel to it, and protects it with OAuth plus a pairing code. You add it to ChatGPT as a custom MCP plugin, and your dot (or any ChatGPT chat) can call its tools.

It does **not** appear under your dot's **Computers** list. It appears as a plugin.

## Requirements

- Node 20+
- `cloudflared` (`brew install cloudflared`)
- `codex` CLI, only for the Codex tools
- A ChatGPT plan that can add custom MCP servers. OpenAI's docs say Pro gets read/fetch tools only and Business/Enterprise get write tools. Plus isn't documented.

## Run

```sh
npm install
npm start
```

It prints a `https://….trycloudflare.com/mcp` URL and a 6-digit pairing code. Then:

1. In ChatGPT on the web, open **Plugins → + → Add custom MCP server**.
2. Paste the URL, choose **OAuth**, accept the warning, and select **Create as a plugin**, then install it.
3. When the approval page opens, enter the pairing code.
4. Ask your dot: `Use the dot-bridge plugin's computer_info tool.`

The quick tunnel URL changes every time it restarts. For a stable URL, run a named Cloudflare tunnel and set `PUBLIC_URL=https://your-host`.

## Tools

| Tool | Read-only |
| --- | --- |
| `computer_info` | yes |
| `list_files` | yes |
| `read_file` | yes |
| `codex_task_status` | yes |
| `write_file` | no |
| `run_command` | no |
| `start_codex_task` | no |

## Settings

| Variable | Default |
| --- | --- |
| `PORT` | `8787` |
| `PUBLIC_URL` | starts a Cloudflare quick tunnel |
| `DOT_BRIDGE_ROOTS` | your home folder (`:`-separated list) |
| `DOT_BRIDGE_DIR` | `~/.dot-bridge` (tokens and activity log) |

## Security

Anyone who passes the approval page can run commands as you. The pairing code is new on every start, and five wrong attempts lock approval until restart. Tokens are kept in `~/.dot-bridge/state.json`; delete that file to revoke every connection. Every tool call is logged to `~/.dot-bridge/activity.log`. Stop the program to cut access immediately.
