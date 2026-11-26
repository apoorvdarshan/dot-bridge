# dot-bridge

Let your ChatGPT dot use your Mac without the ChatGPT desktop app.

dot-bridge is a small Node program. It runs an MCP server on your Mac, opens a Cloudflare tunnel to it, and protects it with OAuth plus a pairing code. You add it to ChatGPT as a custom MCP plugin, and your dot (or any ChatGPT chat) can call its tools.

It does **not** appear under your dot's **Computers** list. It appears as a plugin.

## Requirements

- macOS 15+ for the menu bar app
- Node 20+
- `cloudflared` (`brew install cloudflared`)
- `codex` CLI, only for the Codex tools
- A ChatGPT plan that can add custom MCP servers. OpenAI's docs say Pro gets read/fetch tools only and Business/Enterprise get write tools. Plus isn't documented.

## Menu bar app

`app/` is a small native SwiftUI app (no Electron). It shows in the Dock and the menu bar by default (either can be hidden), and controls the bridge:

- Start/stop switch, status light, and live activity list
- MCP URL and pairing code with copy buttons
- A separate window you can open or hide
- Settings: show in Dock (on by default), open at login, start on launch, allowed folders, fixed public URL, Node path, port

Build it:

```sh
npm install
app/build.sh
open build/dot-bridge.app
```

The app bundles `server.mjs` and its dependencies, and uses the `node` and `cloudflared` installed on your Mac. It is ad-hoc signed, so the first launch may need right-click → Open.

## Run without the app

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
