#!/usr/bin/env python3
"""Persistent bridge for iTerm2's documented Python API.

One helper lifetime owns one official iTerm2 API connection and one generated
opaque connection incarnation. Swift sends serialized newline-delimited JSON
commands over pipes. The bridge does not inspect titles, CWDs, processes,
layouts, Spaces, or visible text and has no send-text/control operation.
"""
import asyncio
import json
import sys
import uuid


def emit(value):
    print(json.dumps(value), flush=True)


async def sessions_and_tabs(app):
    sessions, tabs = [], []
    for window in app.terminal_windows:
        for tab in window.tabs:
            tab_id = getattr(tab, "tab_id", None)
            if tab_id:
                tabs.append(tab_id)
            for session in tab.sessions:
                session_id = getattr(session, "session_id", None)
                if session_id:
                    sessions.append(session_id)
    return sessions, tabs


async def handle(app, command, connection_id):
    operation = command.get("operation")
    if operation == "probe":
        sessions, tabs = await sessions_and_tabs(app)
        return {
            "hostVersion": str(getattr(app, "version", "unknown")),
            "endpointID": "iterm2-python-api",
            "connectionID": connection_id,
            "apiConnected": True,
            "appAvailable": True,
            "sessionIDs": sessions,
            "tabIDs": tabs,
        }
    if operation != "activate":
        return {"failure": "activationRejected", "connectionID": connection_id}
    expected = command.get("expectedConnectionID")
    if expected and expected != connection_id:
        return {"activated": False, "failure": "incarnationChanged", "connectionID": connection_id}
    session_id, tab_id = command.get("sessionID"), command.get("tabID")
    # Re-resolve immediately in this same API connection; no saved object,
    # name, path, tab ordinal, or presentation metadata is ever reused.
    if session_id:
        for window in app.terminal_windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    if getattr(session, "session_id", None) == session_id:
                        await session.async_activate()
                        return {"activated": True, "connectionID": connection_id}
        return {"activated": False, "failure": "targetUnavailable", "connectionID": connection_id}
    if tab_id:
        for window in app.terminal_windows:
            for tab in window.tabs:
                if getattr(tab, "tab_id", None) == tab_id:
                    await tab.async_activate()
                    return {"activated": True, "connectionID": connection_id}
        return {"activated": False, "failure": "targetUnavailable", "connectionID": connection_id}
    if command.get("appOnly") == "true":
        await app.async_activate()
        return {"activated": True, "connectionID": connection_id}
    return {"activated": False, "failure": "activationRejected", "connectionID": connection_id}


async def serve(connection):
    import iterm2
    app = await iterm2.async_get_app(connection)
    connection_id = str(uuid.uuid4())
    loop = asyncio.get_running_loop()
    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            return
        try:
            command = json.loads(line)
            emit(await handle(app, command, connection_id))
        except Exception:
            # A host/API failure ends this helper incarnation. Swift marks it
            # unavailable; only an explicit setup/reprobe may launch another.
            emit({"failure": "apiDisconnected", "connectionID": connection_id})
            return


def main():
    if "--serve" not in sys.argv:
        sys.exit(2)
    try:
        import iterm2
        iterm2.run_until_complete(serve)
    except ModuleNotFoundError:
        emit({"failure": "unsupportedAPI"})
        sys.exit(2)
    except Exception:
        emit({"failure": "apiDisconnected"})
        sys.exit(2)


if __name__ == "__main__":
    main()
