"""Inspect one commit in the current review session's worktree."""

import json
import re
import subprocess
import tempfile
from pathlib import Path

from agent.runtime_cwd import scoped_session_cwd

MAX_OUTPUT = 64_000
GIT = "/run/current-system/sw/bin/git"


def _git(cwd, *args):
    env = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0"}
    with tempfile.TemporaryFile() as output:
        subprocess.run(
            [GIT, "--no-pager", "-c", "core.fsmonitor=false", *args],
            cwd=cwd,
            env=env,
            stdout=output,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=15,
        )
        output.seek(0)
        data = output.read(MAX_OUTPUT + 1)
    return data[:MAX_OUTPUT].decode("utf-8", errors="replace"), len(data) > MAX_OUTPUT


def inspect_commit(args, **_context):
    commit = args.get("commit")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit):
        return json.dumps({"error": "Provide a full lowercase Git commit SHA."})
    cwd = scoped_session_cwd()
    if not cwd or not Path(cwd).is_absolute():
        return json.dumps({"error": "The reviewer has no assigned worktree."})
    try:
        head, _ = _git(cwd, "rev-parse", "--verify", "HEAD")
        status, truncated_status = _git(cwd, "status", "--porcelain", "--ignore-submodules=all")
        patch, truncated_patch = _git(
            cwd, "show", "--no-ext-diff", "--no-textconv", "--format=fuller", "--patch", f"{commit}^{{commit}}", "--"
        )
    except (OSError, subprocess.SubprocessError):
        return json.dumps({"error": "Git could not inspect this commit in the assigned worktree."})
    return json.dumps({
        "head": head.strip(),
        "status": status,
        "status_truncated": truncated_status,
        "commit_diff": patch,
        "diff_truncated": truncated_patch,
    })


def register(ctx):
    ctx.register_tool(
        name="inspect_git_commit",
        toolset="paseo_review_git",
        schema={
            "name": "inspect_git_commit",
            "description": "Read a commit's diff, current HEAD, and working-tree status in the assigned worktree.",
            "parameters": {
                "type": "object",
                "properties": {"commit": {"type": "string", "description": "Full Git commit SHA."}},
                "required": ["commit"],
                "additionalProperties": False,
            },
        },
        handler=inspect_commit,
    )
