// Minimal Cursor/VS Code extension contributor for the AB-141 local endpoint.
// Installation supplies AGENT_ISLAND_CURSOR_SOCKET and a base64 credential by
// an explicit person-controlled setup flow. This extension retains Terminal
// object references only in this extension-host process; it never enumerates
// terminals, matches names/PIDs/titles/paths, emits terminal input, or opens a
// deep link. The Product integration must call registerLiveTerminal with the
// exact owning Agent Session identity and a currently obtained Terminal.
const net = require('net'); const crypto = require('crypto');
let server; const terminals = new Map(); const incarnation = crypto.randomUUID();
function registerLiveTerminal(owner, terminal) {
  const ref = crypto.randomUUID(); terminals.set(ref, { owner, terminal });
  terminal.processId.then(() => {}, () => terminals.delete(ref));
  return ref;
}
function constantEqual(a, b) { return a.length === b.length && crypto.timingSafeEqual(a, b); }
function activate(context) {
  const socketPath = process.env.AGENT_ISLAND_CURSOR_SOCKET;
  const credential = process.env.AGENT_ISLAND_CURSOR_CREDENTIAL_B64;
  if (!socketPath || !credential) return;
  const expected = Buffer.from(credential, 'base64');
  server = net.createServer(socket => {
    let bytes = Buffer.alloc(0); socket.on('data', chunk => { bytes = Buffer.concat([bytes, chunk]); if (bytes.length < 4) return;
      const length = bytes.readUInt32BE(0); if (length > 65536 || bytes.length < length + 4) return;
      let request; try { request = JSON.parse(bytes.subarray(4, length + 4)); } catch { return socket.destroy(); }
      if (!request.credential || !constantEqual(Buffer.from(request.credential, 'base64'), expected)) return socket.destroy();
      const m = request.message; let response = { failure: 'malformedResponse' };
      const binding = m && Object.values(m)[0]; const ref = binding && binding.terminalReference && binding.terminalReference.rawValue;
      if (m.status && terminals.has(ref)) response = { response: { status: { endpointID: 'cursor-extension', incarnation: { rawValue: incarnation }, protocolVersion: 1, cursorVersion: 'unknown', authenticated: true, connected: true, applicationAvailable: true, matchingLiveReferenceCount: 1 } } };
      // reveal only succeeds for this exact retained object. VS Code exposes no
      // documented integrated-terminal focus API, so this contributor returns
      // dispatchRejected rather than synthesize UI automation.
      if (m.revealLiveTerminal) response = terminals.has(ref) ? { failure: 'dispatchRejected' } : { failure: 'terminalUnavailable' };
      const out = Buffer.from(JSON.stringify(response)); const header = Buffer.alloc(4); header.writeUInt32BE(out.length); socket.end(Buffer.concat([header, out]));
    });
  }); server.listen(socketPath); context.subscriptions.push({ dispose: () => { terminals.clear(); server && server.close(); } });
}
function deactivate() { terminals.clear(); if (server) server.close(); }
module.exports = { activate, deactivate, registerLiveTerminal };
