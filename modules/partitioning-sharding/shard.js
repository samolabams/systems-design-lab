// Partitioning & sharding.
//
// Run with Node (no dependencies):  node shard.js
//
// The problem: you have more data than one node can hold, so you split ("shard")
// keys across N nodes. The question is HOW you map a key to a node.
//
//   Naive:       node = hash(key) % N
//   Consistent:  place nodes AND keys on a hash ring; a key belongs to the next
//                node clockwise.
//
// Both spread keys roughly evenly. The difference shows up when N CHANGES: with
// modulo, almost every key moves (a full reshuffle — cache misses, data copies,
// downtime). With a consistent-hash ring, only ~K/N keys move. This script
// measures exactly that.

'use strict';

const crypto = require('crypto');

// 32-bit hash of a string (stable across runs and processes).
function hash(str) {
  return crypto.createHash('md5').update(str).digest().readUInt32BE(0);
}

// --- Strategy 1: naive modulo ----------------------------------------------
function moduloAssign(keys, nodes) {
  const map = new Map();
  for (const k of keys) map.set(k, nodes[hash(k) % nodes.length]);
  return map;
}

// --- Strategy 2: consistent hash ring with virtual nodes -------------------
// Each physical node is placed at VNODES points around the ring so the load
// evens out (without vnodes a ring of 4 nodes can be badly unbalanced).
class HashRing {
  constructor(nodes, vnodes = 150) {
    this.vnodes = vnodes;
    this.ring = []; // sorted [{ point, node }]
    for (const n of nodes) this._add(n);
    this._sort();
  }
  _add(node) {
    for (let i = 0; i < this.vnodes; i++) {
      this.ring.push({ point: hash(`${node}#${i}`), node });
    }
  }
  add(node) { this._add(node); this._sort(); }
  _sort() { this.ring.sort((a, b) => a.point - b.point); }
  // First vnode clockwise from the key's hash owns the key.
  nodeFor(key) {
    const h = hash(key);
    for (const v of this.ring) if (v.point >= h) return v.node;
    return this.ring[0].node; // wrap around
  }
  assign(keys) {
    const map = new Map();
    for (const k of keys) map.set(k, this.nodeFor(k));
    return map;
  }
}

// --- Helpers ----------------------------------------------------------------
function distribution(map, nodes) {
  const counts = Object.fromEntries(nodes.map((n) => [n, 0]));
  for (const node of map.values()) counts[node]++;
  return counts;
}
function moved(before, after) {
  let n = 0;
  for (const [k, node] of before) if (after.get(k) !== node) n++;
  return n;
}
function pct(n, total) { return ((100 * n) / total).toFixed(1) + '%'; }

// --- Experiment -------------------------------------------------------------
const KEYS = Array.from({ length: 10000 }, (_, i) => `user:${i}`);
const NODES4 = ['nodeA', 'nodeB', 'nodeC', 'nodeD'];
const NODES5 = [...NODES4, 'nodeE'];

console.log(`Sharding ${KEYS.length} keys across ${NODES4.length} nodes, then adding a 5th.\n`);

// Modulo
const modBefore = moduloAssign(KEYS, NODES4);
const modAfter = moduloAssign(KEYS, NODES5);
console.log('Naive modulo  hash(key) % N');
console.log('  distribution (4 nodes):', distribution(modBefore, NODES4));
console.log(`  keys moved when adding node 5: ${moved(modBefore, modAfter)} / ${KEYS.length}  (${pct(moved(modBefore, modAfter), KEYS.length)})`);
for (const key of ['user:42', 'user:777', 'order:123']) {
  console.log(`  example ${key}: hash=${hash(key)} -> ${modBefore.get(key)} with 4 nodes`);
}

// Consistent
const ring = new HashRing(NODES4);
const ringBefore = ring.assign(KEYS);
ring.add('nodeE');
const ringAfter = ring.assign(KEYS);
console.log('\nConsistent hash ring (150 vnodes/node)');
console.log('  distribution (4 nodes):', distribution(ringBefore, NODES4));
console.log(`  keys moved when adding node 5: ${moved(ringBefore, ringAfter)} / ${KEYS.length}  (${pct(moved(ringBefore, ringAfter), KEYS.length)})`);
for (const key of ['user:42', 'user:777', 'order:123']) {
  console.log(`  example ${key}: hash=${hash(key)} -> ${ringBefore.get(key)} before adding nodeE, ${ringAfter.get(key)} after`);
}

const ringFewVnodes = new HashRing(NODES4, 1);
const ringManyVnodes = new HashRing(NODES4, 150);
console.log('\nVirtual nodes smooth distribution');
console.log('  1 vnode/node distribution:', distribution(ringFewVnodes.assign(KEYS), NODES4));
console.log('  150 vnodes/node distribution:', distribution(ringManyVnodes.assign(KEYS), NODES4));

const ideal = KEYS.length / NODES5.length;
console.log(`\nIdeal share for the new node: ~${Math.round(ideal)} keys (${pct(ideal, KEYS.length)}).`);
console.log('Modulo reshuffles almost everything; the ring moves only ~one node\'s worth.');
