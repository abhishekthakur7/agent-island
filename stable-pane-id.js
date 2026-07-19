"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isStablePaneId = isStablePaneId;
exports.isTerminalLeafId = isTerminalLeafId;
exports.makePaneKey = makePaneKey;
exports.parsePaneKey = parsePaneKey;
exports.parseLegacyNumericPaneKey = parseLegacyNumericPaneKey;
// Why: paneKey crosses renderer reloads, PTY env, hook IPC, and retained UI
// rows, so it must use the durable terminal-layout leaf UUID instead of the
// renderer-local numeric PaneManager id.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function isStablePaneId(value) {
    return UUID_RE.test(value);
}
function isTerminalLeafId(value) {
    return isStablePaneId(value);
}
function makePaneKey(tabId, stableLeafId) {
    if (!tabId || tabId.includes(':')) {
        throw new Error('tabId must be non-empty and must not contain ":"');
    }
    if (!isTerminalLeafId(stableLeafId)) {
        throw new Error('stableLeafId must be a UUID');
    }
    return `${tabId}:${stableLeafId}`;
}
function parsePaneKey(paneKey) {
    const first = paneKey.indexOf(':');
    if (first <= 0 || first !== paneKey.lastIndexOf(':') || first === paneKey.length - 1) {
        return null;
    }
    const tabId = paneKey.slice(0, first);
    const leafId = paneKey.slice(first + 1);
    if (!isTerminalLeafId(leafId)) {
        return null;
    }
    return { tabId, leafId, stablePaneId: leafId };
}
function parseLegacyNumericPaneKey(paneKey) {
    if (typeof paneKey !== 'string' || paneKey.length > 256) {
        return null;
    }
    const trimmed = paneKey.trim();
    const delimiter = trimmed.indexOf(':');
    if (delimiter <= 0 ||
        delimiter !== trimmed.lastIndexOf(':') ||
        delimiter === trimmed.length - 1) {
        return null;
    }
    const numericPaneId = trimmed.slice(delimiter + 1);
    if (!/^\d+$/.test(numericPaneId)) {
        return null;
    }
    return { tabId: trimmed.slice(0, delimiter), numericPaneId, paneKey: trimmed };
}
