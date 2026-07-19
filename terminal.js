"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TERMINAL_HANDLERS = void 0;
const codex_command_classification_1 = require("../codex-command-classification");
const format_1 = require("../format");
const flags_1 = require("../flags");
const runtime_client_1 = require("../runtime-client");
const selectors_1 = require("../selectors");
// Why: terminal wait legitimately needs to outlive the CLI's default RPC
// timeout. Even without an explicit server timeout, the client must allow
// long waits instead of failing at the generic 15s transport cap.
const DEFAULT_TERMINAL_WAIT_RPC_TIMEOUT_MS = 5 * 60 * 1000;
const terminalFocusHandler = async ({ flags, client, cwd, json }) => {
    const result = await client.call('terminal.focus', {
        terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client)
    });
    (0, format_1.printResult)(result, json, format_1.formatTerminalFocus);
};
exports.TERMINAL_HANDLERS = {
    'terminal list': async ({ flags, client, cwd, json }) => {
        const result = await client.call('terminal.list', {
            worktree: await (0, selectors_1.getOptionalWorktreeSelector)(flags, 'worktree', cwd, client),
            limit: (0, flags_1.getOptionalPositiveIntegerFlag)(flags, 'limit')
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalList);
    },
    'terminal show': async ({ flags, client, cwd, json }) => {
        const result = await client.call('terminal.show', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client)
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalShow);
    },
    'terminal read': async ({ flags, client, cwd, json }) => {
        const cursorFlag = (0, flags_1.getOptionalStringFlag)(flags, 'cursor');
        const cursor = cursorFlag !== undefined && /^\d+$/.test(cursorFlag)
            ? Number.parseInt(cursorFlag, 10)
            : undefined;
        if (cursorFlag !== undefined && cursor === undefined) {
            throw new runtime_client_1.RuntimeClientError('invalid_argument', '--cursor must be a non-negative integer');
        }
        const result = await client.call('terminal.read', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client),
            ...(cursor !== undefined ? { cursor } : {}),
            limit: (0, flags_1.getOptionalPositiveIntegerFlag)(flags, 'limit')
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalRead);
    },
    'terminal send': async ({ flags, client, cwd, json }) => {
        const result = await client.call('terminal.send', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client),
            text: (0, flags_1.getOptionalStringFlag)(flags, 'text'),
            enter: flags.get('enter') === true,
            interrupt: flags.get('interrupt') === true,
            client: { id: 'orca-cli', type: 'desktop' }
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalSend);
    },
    'terminal wait': async ({ flags, client, cwd, json }) => {
        const timeoutMs = (0, flags_1.getOptionalPositiveIntegerFlag)(flags, 'timeout-ms');
        const result = await client.call('terminal.wait', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client),
            for: (0, flags_1.getRequiredStringFlag)(flags, 'for'),
            timeoutMs
        }, {
            timeoutMs: timeoutMs ? timeoutMs + 5000 : DEFAULT_TERMINAL_WAIT_RPC_TIMEOUT_MS
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalWait);
        if (result.result.wait.satisfied === false) {
            // Why: callers commonly chain `terminal wait && terminal send`; a
            // structured blocked result is still an unsatisfied wait condition.
            process.exitCode = 1;
        }
    },
    'terminal stop': async ({ flags, client, cwd, json }) => {
        const result = await client.call('terminal.stop', {
            worktree: await (0, selectors_1.getRequiredWorktreeSelector)(flags, 'worktree', cwd, client)
        });
        (0, format_1.printResult)(result, json, (value) => `Stopped ${value.stopped} terminals.`);
    },
    'terminal rename': async ({ flags, client, cwd, json }) => {
        const result = await client.call('terminal.rename', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client),
            title: (0, flags_1.getOptionalStringFlag)(flags, 'title') ?? null
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalRename);
    },
    'terminal create': async ({ flags, client, cwd, json }) => {
        if (client.isRemote && !flags.has('worktree')) {
            throw new runtime_client_1.RuntimeClientError('invalid_argument', 'Remote terminal create requires --worktree because the client cwd cannot identify a server worktree.');
        }
        const command = (0, flags_1.getOptionalStringFlag)(flags, 'command');
        const useRendererBackedInteractiveTerminal = !client.isRemote && (0, codex_command_classification_1.shouldUseRendererBackedInteractiveTerminal)(command);
        const focus = flags.get('focus') === true;
        const result = await client.call('terminal.create', {
            worktree: await (0, selectors_1.getBrowserWorktreeSelector)(flags, cwd, client),
            command,
            title: (0, flags_1.getOptionalStringFlag)(flags, 'title'),
            // Why: interactive local agent TUIs need the renderer-backed terminal
            // path for browser-side features, but CLI creates must stay backgrounded
            // unless the caller explicitly asks for focus.
            focus,
            ...(focus ? { presentation: 'focused' } : {}),
            ...(useRendererBackedInteractiveTerminal ? { rendererBacked: true, activate: focus } : {})
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalCreate);
    },
    // `focus` resolves to this canonical path via CommandSpec.aliases before dispatch.
    'terminal switch': terminalFocusHandler,
    'terminal close': async ({ flags, client, cwd, json }) => {
        const method = flags.get('tab') === true ? 'terminal.closeTab' : 'terminal.close';
        const result = await client.call(method, {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client)
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalClose);
    },
    'terminal split': async ({ flags, client, cwd, json }) => {
        const directionFlag = (0, flags_1.getOptionalStringFlag)(flags, 'direction');
        if (directionFlag !== undefined &&
            directionFlag !== 'horizontal' &&
            directionFlag !== 'vertical') {
            throw new runtime_client_1.RuntimeClientError('invalid_argument', '--direction must be horizontal or vertical');
        }
        const result = await client.call('terminal.split', {
            terminal: await (0, selectors_1.getTerminalHandle)(flags, cwd, client),
            direction: directionFlag,
            command: (0, flags_1.getOptionalStringFlag)(flags, 'command')
        });
        (0, format_1.printResult)(result, json, format_1.formatTerminalSplit);
    }
};
