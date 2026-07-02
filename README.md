# Harmonia

A personal SDLC that runs on top of Claude Code: thin lifecycle commands orchestrate a thirteen-agent roster bound by the 4 Karpathy rules, hooks deterministically enforce everything a machine can check, and captured knowledge compounds across sessions and projects.

## Why "Harmonia"

From the Portuguese word for harmony, and for Harmonia, the Greek goddess of harmony — the cosmos as ordered music and balance (the Music of the Spheres). The name evokes order, structure, and beauty: exactly what a good SDLC provides. It is instantly readable and pronounceable, and it feels classical and mythic.

## Install

```bash
claude plugin marketplace add foliveira/harmonia
claude plugin install harmonia
```

Every commit to this repo is an auto-update on installed machines (the plugin declares no version). Live behavior runs from the plugin cache: after changing the engine, commit, run `/plugin update`, and open a fresh session.

### Disabling in a specific repo (client work)

Add to that repo's `.claude/settings.local.json`:

```json
{ "enabledPlugins": { "harmonia": false } }
```

Emergency brake: set `HARMONIA_DISABLE=1` in the environment — the session-start hook checks it first and stays silent.

## The roster

ideator · scoper · planner · implementer · test engineer · reviewer (review lead) · simplifier · knowledge curator · committer · debugger · documentation producer · documentation reviewer · rubber duck

## Credits

Harmonia systematizes my own workflow. It vendors nothing, but draws inspiration from:
[multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) ·
[EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) ·
[Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) ·
[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) ·
[mattpocock/skills](https://github.com/mattpocock/skills)

MIT licensed.
