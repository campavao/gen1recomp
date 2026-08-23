// node --test  (from this directory)
//
// Drives the relay over real sockets on an ephemeral port: host, join,
// roster fan-out, unicast and broadcast routing, the error reasons the
// client shows, locking, and the host leaving.

import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { createRelay, CODE_ALPHABET, CODE_LENGTH } from "./server.js";

class Client {
  constructor(port) {
    this.socket = net.createConnection({ port, host: "127.0.0.1" });
    this.socket.setEncoding("utf8");
    this.buf = "";
    this.inbox = [];
    this.waiters = [];
    this.closed = false;
    this.socket.on("data", (chunk) => {
      this.buf += chunk;
      let nl;
      while ((nl = this.buf.indexOf("\n")) >= 0) {
        const line = this.buf.slice(0, nl);
        this.buf = this.buf.slice(nl + 1);
        if (line) this.push(JSON.parse(line));
      }
    });
    this.socket.on("close", () => { this.closed = true; this.push({ type: "__closed" }); });
  }

  ready() {
    return new Promise((resolve, reject) => {
      this.socket.once("connect", resolve);
      this.socket.once("error", reject);
    });
  }

  push(msg) {
    const w = this.waiters.shift();
    if (w) w(msg); else this.inbox.push(msg);
  }

  send(msg) {
    this.socket.write(JSON.stringify(msg) + "\n");
  }

  raw(text) {
    this.socket.write(text);
  }

  next(timeoutMs = 2000) {
    if (this.inbox.length) return Promise.resolve(this.inbox.shift());
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("timed out waiting for a message")), timeoutMs);
      this.waiters.push((msg) => { clearTimeout(timer); resolve(msg); });
    });
  }

  // skip messages until one of the given type arrives
  async until(type, timeoutMs = 2000) {
    for (;;) {
      const msg = await this.next(timeoutMs);
      if (msg.type === type) return msg;
    }
  }

  end() {
    this.socket.end();
    this.socket.destroy();
  }
}

async function withRelay(fn, limits) {
  const relay = createRelay({ limits });
  const addr = await relay.listen(0, "127.0.0.1");
  try {
    await fn(addr.port, relay);
  } finally {
    await relay.close();
  }
}

async function connect(port) {
  const c = new Client(port);
  await c.ready();
  return c;
}

test("host gets a code in the entry-widget alphabet and a roster of one", async () => {
  await withRelay(async (port) => {
    const a = await connect(port);
    a.send({ type: "host_room", name: "RED" });
    const hosted = await a.next();
    assert.equal(hosted.type, "room_hosted");
    assert.equal(hosted.id, 1);
    assert.equal(hosted.code.length, CODE_LENGTH);
    for (const ch of hosted.code) assert.ok(CODE_ALPHABET.includes(ch), `code char ${ch}`);
    const roster = await a.next();
    assert.equal(roster.type, "roster");
    assert.equal(roster.host, 1);
    assert.deepEqual(roster.members, [{ id: 1, name: "RED" }]);
    a.end();
  });
});

test("join by code: everyone sees the roster grow, names are cleaned", async () => {
  await withRelay(async (port) => {
    const a = await connect(port);
    a.send({ type: "host_room", name: "RED" });
    const { code } = await a.next();
    await a.next(); // roster

    const b = await connect(port);
    b.send({ type: "join_room", code: code.toLowerCase(), name: "  blue\x01toolongname " });
    const joined = await b.next();
    assert.equal(joined.type, "room_joined");
    assert.equal(joined.id, 2);
    assert.equal(joined.host, 1);
    assert.equal(joined.code, code);

    const rosterB = await b.next();
    const rosterA = await a.next();
    assert.deepEqual(rosterA, rosterB);
    assert.deepEqual(rosterA.members.map((m) => m.name), ["RED", "bluetoolon"]);
    a.end(); b.end();
  });
});

test("unicast reaches one member, broadcast reaches everyone else", async () => {
  await withRelay(async (port) => {
    const a = await connect(port);
    a.send({ type: "host_room", name: "A" });
    const { code } = await a.next();
    await a.next();
    const b = await connect(port);
    b.send({ type: "join_room", code, name: "B" });
    await b.next(); await b.next(); await a.next();
    const c = await connect(port);
    c.send({ type: "join_room", code, name: "C" });
    await c.next(); await c.next(); await a.next(); await b.next();

    a.send({ type: "to", id: 3, m: { t: "hi", n: 1 } });
    const got = await c.next();
    assert.deepEqual(got, { type: "recv", from: 1, m: { t: "hi", n: 1 } });

    b.send({ type: "all", m: { t: "step", d: "up" } });
    const ga = await a.next();
    const gc = await c.next();
    assert.deepEqual(ga, { type: "recv", from: 2, m: { t: "step", d: "up" } });
    assert.deepEqual(gc, ga);

    // the sender never hears its own broadcast, and a unicast to yourself
    // or to nobody is dropped rather than echoed
    b.send({ type: "to", id: 2, m: { t: "self" } });
    b.send({ type: "to", id: 99, m: { t: "nobody" } });
    b.send({ type: "ping", t: 7 });
    const pong = await b.next();
    assert.deepEqual(pong, { type: "pong", t: 7 });
    a.end(); b.end(); c.end();
  });
});

test("join errors: not_found, locked, full, already_in_room", async () => {
  await withRelay(async (port) => {
    const a = await connect(port);
    a.send({ type: "host_room", name: "A" });
    const { code } = await a.next();
    await a.next();

    const x = await connect(port);
    x.send({ type: "join_room", code: "ZZZZZZ", name: "X" });
    assert.deepEqual(await x.next(), { type: "room_error", reason: "not_found" });

    a.send({ type: "lock_room", locked: true });
    x.send({ type: "join_room", code, name: "X" });
    assert.deepEqual(await x.next(), { type: "room_error", reason: "locked" });
    a.send({ type: "lock_room", locked: false });

    x.send({ type: "join_room", code, name: "X" });
    assert.equal((await x.next()).type, "room_joined");
    await x.next(); await a.next();

    const y = await connect(port);
    y.send({ type: "join_room", code, name: "Y" });
    assert.deepEqual(await y.next(), { type: "room_error", reason: "full" });

    x.send({ type: "host_room", name: "X" });
    assert.deepEqual(await x.next(), { type: "room_error", reason: "already_in_room" });
    a.end(); x.end(); y.end();
  }, { members: 2 });
});

test("a guest leaving updates the roster; the host leaving closes the room", async () => {
  await withRelay(async (port, relay) => {
    const a = await connect(port);
    a.send({ type: "host_room", name: "A" });
    const { code } = await a.next();
    await a.next();
    const b = await connect(port);
    b.send({ type: "join_room", code, name: "B" });
    await b.next(); await b.next(); await a.next();
    const c = await connect(port);
    c.send({ type: "join_room", code, name: "C" });
    await c.next(); await c.next(); await a.next(); await b.next();

    b.end();
    const rosterA = await a.until("roster");
    assert.deepEqual(rosterA.members.map((m) => m.id), [1, 3]);
    const rosterC = await c.until("roster");
    assert.deepEqual(rosterC.members.map((m) => m.id), [1, 3]);

    a.send({ type: "leave_room" });
    const closed = await c.until("room_closed");
    assert.equal(closed.reason, "left");
    assert.equal(relay.rooms.size, 0);

    // ...and the code is gone
    c.send({ type: "join_room", code, name: "C" });
    assert.deepEqual(await c.next(), { type: "room_error", reason: "not_found" });
    a.end(); c.end();
  });
});

test("garbage lines are dropped, a flood of them disconnects", async () => {
  await withRelay(async (port) => {
    const a = await connect(port);
    a.raw("not json\n[1,2]\n{\"noType\":1}\n");
    a.send({ type: "ping" });
    assert.equal((await a.next()).type, "pong");
    for (let i = 0; i < 30; i++) a.raw("garbage\n");
    const closed = await a.until("__closed");
    assert.equal(closed.type, "__closed");
  }, { badLines: 5 });
});
