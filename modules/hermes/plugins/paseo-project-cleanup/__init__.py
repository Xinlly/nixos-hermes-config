"""Project Manager's final filesystem cleanup on the WSL host."""

import json
import os
import re
import shutil
import stat
from pathlib import Path

from acp_adapter.edit_approval import EditProposal
from gateway.session_local_editor import request_editor_edit

WORKSPACE = Path("/var/lib/hermes/workspace")
PASEO = WORKSPACE.parent / ".paseo"
TOOL = "delete_archived_project_directory"


def _records(name):
    with (PASEO / "projects" / f"{name}.json").open(encoding="utf-8") as file:
        return json.load(file)


def _agents():
    for path in (PASEO / "agents").glob("*/*.json"):
        with path.open(encoding="utf-8") as file:
            yield json.load(file)


def _verify_scope(project_id, path, session_id):
    if not session_id:
        raise ValueError("A live Paseo Project Manager session is required.")
    if path == WORKSPACE or not path.is_relative_to(WORKSPACE) or path.resolve(strict=True) != path:
        raise ValueError("Use the canonical path of a directory inside Workspace.")
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError("The archived project's root must be a regular directory.")

    projects = _records("projects")
    project = next((item for item in projects if item["projectId"] == project_id), None)
    if not project or not project.get("archivedAt") or project["rootPath"] != str(path):
        raise ValueError("The project must be archived and its exact registered root must match.")
    workspaces = _records("workspaces")
    mains = {
        item["workspaceId"] for item in workspaces
        if item["projectId"] == project_id and item.get("archivedAt")
        and item["cwd"] == str(path) and item["kind"] != "worktree"
    }
    agents = list(_agents())
    managers = {
        item["id"] for item in agents
        if item["provider"] == "project-manager" and not item.get("archivedAt")
        and (item.get("persistence") or {}).get("sessionId") == session_id
    }
    if len(managers) != 1 or not any(
        item["provider"] == "coordinator" and item.get("archivedAt")
        and item.get("workspaceId") in mains
        and item.get("labels", {}).get("paseo.parent-agent-id") in managers
        for item in agents
    ):
        raise ValueError("The main workspace must have belonged to your archived direct coordinator.")
    for item in workspaces:
        if not item.get("archivedAt") and (
            item["projectId"] == project_id or any(
                item.get(key) and Path(item[key]).resolve().is_relative_to(path)
                for key in ("cwd", "mainRepoRoot", "worktreeRoot")
            )
        ):
            raise ValueError("An active Paseo workspace still depends on the directory or project.")
    for item in projects:
        if item["projectId"] != project_id and not item.get("archivedAt"):
            if Path(item["rootPath"]).resolve().is_relative_to(path):
                raise ValueError("An active Paseo project shares this directory tree.")
    for item in agents:
        if not item.get("archivedAt") and Path(item["cwd"]).resolve().is_relative_to(path):
            raise ValueError("An active Paseo agent still uses the directory.")
    with Path("/proc/self/mountinfo").open(encoding="utf-8") as mounts:
        for line in mounts:
            mount = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), line.split()[4])
            if Path(mount).is_relative_to(path):
                raise ValueError("The project directory contains a mounted filesystem.")
    return info.st_dev, info.st_ino, info.st_ctime_ns


def _remove(path, identity):
    if not shutil.rmtree.avoids_symlink_attacks:
        raise ValueError("Safe directory removal is unavailable on this host.")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    parent = os.open(WORKSPACE, flags)
    try:
        for part in path.parent.relative_to(WORKSPACE).parts:
            child = os.open(part, flags, dir_fd=parent)
            os.close(parent)
            parent = child
        entry = os.stat(path.name, dir_fd=parent, follow_symlinks=False)
        if (entry.st_dev, entry.st_ino, entry.st_ctime_ns) != identity:
            raise ValueError("The target changed before removal. Recheck before trying again.")
        shutil.rmtree(path.name, dir_fd=parent)
    finally:
        os.close(parent)


def delete_archived_project_directory(args, session_id=None):
    path = Path(args["path"])
    project_id = args["project_id"]
    try:
        identity = _verify_scope(project_id, path, session_id)
        approved = request_editor_edit(EditProposal(
            tool_name=TOOL,
            path=str(path),
            old_text=f"Archived Paseo project {project_id}: directory and all local files",
            new_text="PERMANENTLY DELETE THIS DIRECTORY AND ALL CONTENTS",
            arguments={"path": str(path), "project_id": project_id},
        ))
        if not approved:
            return {"error": "Deletion requires one-time user approval for this exact directory."}
        if _verify_scope(project_id, path, session_id) != identity:
            return {"error": "The target changed while waiting for approval."}
        _remove(path, identity)
    except (OSError, RuntimeError, ValueError) as exc:
        return {"error": str(exc)}
    return {"project_id": project_id, "removed_path": str(path)}


def register(ctx):
    ctx.register_tool(
        name=TOOL,
        toolset="paseo_project_cleanup",
        schema={
            "name": TOOL,
            "description": "Permanently remove only your already archived project's exact registered "
                           "main directory after a separate, one-time approval in Paseo.",
            "parameters": {
                "type": "object",
                "properties": {
                    "project_id": {"type": "string"},
                    "path": {"type": "string", "description": "Exact canonical absolute directory path."},
                },
                "required": ["project_id", "path"],
                "additionalProperties": False,
            },
        },
        handler=delete_archived_project_directory,
    )
