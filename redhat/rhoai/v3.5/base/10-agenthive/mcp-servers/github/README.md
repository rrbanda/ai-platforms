# GitHub MCP Server

## Overview

The GitHub MCP server enables Git-based operations — creating pull requests, managing branches, searching code, and pushing configuration changes. This is essential for Tier 2 operations where config changes go through Git.

## Source

[@modelcontextprotocol/server-github](https://github.com/modelcontextprotocol/servers/tree/main/src/github)

## Transport

`stdio` — Runs as a subprocess via `npx`.

## Required Credentials

| Variable | Description |
|----------|-------------|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub PAT with `repo` scope |

## Tool Catalog (26 tools)

### Core Operations
- `create_pull_request` — Create a PR with title, body, and base branch
- `get_file_contents` — Read file content from a repository
- `push_files` — Push multiple files in a single commit
- `create_branch` — Create a new branch from a ref
- `create_or_update_file` — Create or update a single file

### Discovery
- `list_branches` — List repository branches
- `list_commits` — List recent commits
- `search_code` — Search code across repositories

## Disconnected Environments

GitHub MCP is typically unavailable in air-gapped clusters. Options:
1. **Gitea MCP** — Use a Gitea-compatible MCP server for internal Git
2. **GitLab MCP** — Use GitLab's MCP server if available
3. **Disable** — Remove from agent config; the agent will suggest manual Git operations instead
