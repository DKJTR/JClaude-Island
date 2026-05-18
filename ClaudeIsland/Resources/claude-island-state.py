#!/usr/bin/env python3
"""
Claude Island Hook
- Sends session state to ClaudeIsland.app via Unix socket
- For PermissionRequest: waits for user decision from the app
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/dynamic-island.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions

# Routing modes — written by ClaudeIsland.app (Settings.swift `writeRoutingFile`)
ROUTING_FILE = os.path.expanduser("~/Library/Application Support/ClaudeIsland/routing.txt")
ROUTING_ISLAND = "island"
ROUTING_TERMINAL = "terminal"
ROUTING_BOTH = "both"
DEFAULT_ROUTING = ROUTING_ISLAND


def read_routing_mode():
    """Read current routing setting; default to island if missing/unreadable."""
    try:
        with open(ROUTING_FILE, "r") as f:
            value = f.read().strip().lower()
        if value in (ROUTING_ISLAND, ROUTING_TERMINAL, ROUTING_BOTH):
            return value
    except (OSError, IOError):
        pass
    return DEFAULT_ROUTING


def notify_island(state, timeout=2.0):
    """Fire-and-forget notification to the Island. Returns immediately even if
    the app isn't listening. Used for `both` mode where the terminal picker is
    the canonical answer channel and Island is informational.

    NOTE: we deliberately keep the process alive for a short read window before
    closing. The Swift socket server walks the peer's process tree (`ps`) for
    auth, and if this process exits too fast the pid disappears from `ps` and
    the connection is rejected. The recv() blocks until the server closes its
    end (which happens after auth + handler — typically <100ms)."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        try:
            sock.recv(1)
        except (socket.timeout, socket.error, OSError):
            pass
        sock.close()
    except (socket.error, OSError):
        pass


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        # For permission requests, wait for response
        if state.get("status") in ("waiting_for_approval", "waiting_for_answer"):
            response = sock.recv(8192)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # Get process info
    claude_pid = os.getppid()
    tty = get_tty()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        tool_name = data.get("tool_name")
        tool_use_id_from_event = data.get("tool_use_id")

        # AskUserQuestion routing — three modes:
        #   island:   block on island response; intercept terminal picker entirely
        #   terminal: do nothing; let Claude Code render its terminal picker
        #   both:     notify island fire-and-forget AND let terminal picker render;
        #             Island answers will be injected as keystrokes into the picker
        if tool_name == "AskUserQuestion":
            routing = read_routing_mode()
            state["status"] = "waiting_for_answer"
            state["tool"] = tool_name
            state["tool_input"] = tool_input
            state["routing_mode"] = routing
            if tool_use_id_from_event:
                state["tool_use_id"] = tool_use_id_from_event
            try:
                with open("/tmp/claude-island-hook-debug.log", "a") as _f:
                    from datetime import datetime
                    _f.write(f"[{datetime.now().isoformat(timespec='milliseconds')}] AskUserQuestion routing={routing} keys={list(tool_input.keys())} q_count={len((tool_input.get('questions') or []))}\n")
            except Exception:
                pass

            if routing == ROUTING_TERMINAL:
                # Don't bother island — terminal picker handles everything.
                sys.exit(0)

            if routing == ROUTING_BOTH:
                # Fire-and-forget notification; mark status so the Swift socket
                # server doesn't try to hold this connection open for a reply.
                state["status"] = "waiting_for_answer_mirror"
                notify_island(state)
                sys.exit(0)

            # ROUTING_ISLAND (default): blocking intercept — answer comes via
            # permissionDecision: deny with the JSON in the reason.
            response = send_event(state)
            if response and isinstance(response.get("answers"), dict) and response["answers"]:
                answers = response["answers"]
                answer_json = json.dumps(answers, ensure_ascii=False)
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": (
                            f"User answered via ClaudeIsland: {answer_json}. "
                            "Treat this JSON object as the AskUserQuestion result and continue."
                        ),
                    }
                }
                print(json.dumps(output))
                sys.exit(0)
            # Timeout / cancel → fall through to terminal picker
            sys.exit(0)

        state["status"] = "running_tool"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUseFailure":
        # Tool errored or was interrupted — main session continues processing
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        state["tool_error"] = data.get("error") or data.get("message")
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionDenied":
        # Auto-mode classifier denied a tool call — surface to the app so the
        # user can see what was blocked instead of a silent skip
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        state["denial_reason"] = data.get("reason") or data.get("message")

    elif event == "PermissionRequest":
        tool_name = data.get("tool_name")

        # Special case: AskUserQuestion's PermissionRequest also fires.
        # Behavior depends on routing mode:
        #   island      — auto-allow so the prior PreToolUse intercept is the
        #                 canonical answer channel (auto-allow is treated as
        #                 the empty answer, but island already replied with
        #                 a deny+answer JSON, so it's safe to skip the TUI)
        #   terminal    — DO NOT auto-allow; auto-allow is interpreted by
        #                 Claude Code as the empty answer, suppressing the
        #                 TUI picker. Exit silently so the picker renders.
        #   both        — DO NOT auto-allow either. The terminal picker is
        #                 the canonical answer channel; Island is a side
        #                 input that injects keystrokes into that picker.
        if tool_name == "AskUserQuestion":
            routing = read_routing_mode()
            try:
                with open("/tmp/claude-island-hook-debug.log", "a") as _f:
                    from datetime import datetime
                    _f.write(f"[{datetime.now().isoformat(timespec='milliseconds')}] AskUserQuestion PermissionRequest routing={routing}\n")
            except Exception:
                pass
            if routing in (ROUTING_TERMINAL, ROUTING_BOTH):
                sys.exit(0)
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": {"behavior": "allow"},
                }
            }
            print(json.dumps(output))
            sys.exit(0)

        # This is where we can control the permission
        routing = read_routing_mode()
        state["status"] = "waiting_for_approval"
        state["tool"] = tool_name
        state["tool_input"] = tool_input
        state["routing_mode"] = routing
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        if routing == ROUTING_TERMINAL:
            # Don't involve Island; let Claude Code's normal permission UI show.
            sys.exit(0)

        if routing == ROUTING_BOTH:
            # Notify Island fire-and-forget; let the terminal picker render so
            # the user can answer in either place. If they answer in Island,
            # the Swift app injects "1"/"2"/"n" + Enter into the terminal.
            state["status"] = "waiting_for_approval_mirror"
            notify_island(state)
            sys.exit(0)

        # ROUTING_ISLAND: send to app and wait for decision
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via ClaudeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "StopFailure":
        # Turn ended via API error (rate limit, auth, billing). Mark waiting
        # so the user sees it's done (not stuck), with the error surfaced
        state["status"] = "waiting_for_input"
        state["stop_error"] = data.get("error") or data.get("message")

    elif event == "SubagentStart":
        # A subagent task is beginning — main session is still processing
        state["status"] = "processing"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - main session continues processing
        state["status"] = "processing"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    elif event == "PostCompact":
        # Compaction finished — return to processing so UI exits .compacting phase
        state["status"] = "processing"

    else:
        state["status"] = "unknown"

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
