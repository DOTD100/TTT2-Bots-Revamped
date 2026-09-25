#!/usr/bin/env node
"use strict";

/**
 * glua-check - GLua-aware static checks for TTT-Bots-2.
 *
 * What it is: a small harness that reuses two things shipped inside the user's installed
 * "GLua Enhanced" VSCode extension (venner.vscode-glua-enhanced):
 *
 *   1. node_modules/gluaparse - a real GLua parser (understands `continue`, `!=`, `&&`,
 *      `||`, `!`, `//`), recovered from dist/extension.bundle.js.map. This replaces the old
 *      luaparser sweep, which could only cope with GLua code after rewriting every
 *      `continue` into `do end`.
 *   2. resources/wiki.json - a scrape of the GMod wiki: every global, library and class
 *      member (with realm flags), the full hook list, panels, and 3000+ enum members. This
 *      is what makes API-level checks possible offline.
 *
 * Nothing from the extension is copied into this repository: the parser is extracted into
 * the OS temp directory at run time and cached there.
 *
 * Checks:
 *   1. syntax   every lua/ file parses under the GLua grammar.
 *   2. hooks    every hook name used is a real hook (wiki), a TTT2 hook, or one registered
 *               somewhere in this tree. Hooks that are run but never registered here are
 *               listed as notes (they are extension points for other addons).
 *   3. api      `library.member` references and called globals that do not exist in the wiki
 *               database. A reference the file nil-checks first ("if not draw.DrawAvatar then
 *               return end") is a *note*, not a failure - that is deliberate feature
 *               detection for another addon.
 *
 * Usage:  node tools/glua-check/check.js
 * Exit:   0 clean, 1 findings, 2 the extension/parser could not be found.
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const ADDON_ROOT = path.resolve(__dirname, "..", "..");
const LUA_DIR = path.join(ADDON_ROOT, "lua");
const TTT2_DIR = path.join(ADDON_ROOT, "..", "TTT2-master");

// --------------------------------------------------------------------------------------
// 1. find the extension and recover the parser
// --------------------------------------------------------------------------------------

function findExtension() {
	const base = path.join(os.homedir(), ".vscode", "extensions");
	if (!fs.existsSync(base)) return null;

	// Newest version last, so "2.10.0" beats "2.9.1".
	const dirs = fs
		.readdirSync(base)
		.filter((name) => /glua-enhanced/i.test(name))
		.map((name) => path.join(base, name))
		.sort((a, b) => path.basename(a).localeCompare(path.basename(b), undefined, { numeric: true }));

	for (const dir of dirs.reverse()) {
		const bundle = path.join(dir, "dist", "extension.bundle.js.map");
		const wiki = path.join(dir, "resources", "wiki.json");
		if (fs.existsSync(bundle)) return { dir, bundle, wiki: fs.existsSync(wiki) ? wiki : null };
	}
	return null;
}

function loadParser(extension) {
	const map = JSON.parse(fs.readFileSync(extension.bundle, "utf8"));
	const index = map.sources.findIndex((s) => /node_modules\/gluaparse\/gluaparse\.js$/.test(s));
	if (index < 0) throw new Error("gluaparse not found inside " + extension.bundle);

	const source = map.sourcesContent[index];
	const tag = crypto
		.createHash("md5")
		.update(path.basename(extension.dir) + ":" + source.length)
		.digest("hex");
	const cache = path.join(os.tmpdir(), "glua-check-gluaparse-" + tag + ".js");
	if (!fs.existsSync(cache)) fs.writeFileSync(cache, source);

	return require(cache);
}

// --------------------------------------------------------------------------------------
// 2. collect facts about every Lua file
// --------------------------------------------------------------------------------------

function luaFiles(dir, out) {
	out = out || [];
	if (!fs.existsSync(dir)) return out;
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) luaFiles(full, out);
		else if (entry.name.endsWith(".lua")) out.push(full);
	}
	return out;
}

/** Walks a luaparse AST, calling cb(node, parent) for every typed node. */
function walk(node, cb, parent) {
	if (!node || typeof node !== "object") return;
	if (Array.isArray(node)) {
		for (const child of node) walk(child, cb, parent);
		return;
	}
	if (typeof node.type === "string") cb(node, parent);
	for (const key of Object.keys(node)) {
		if (key === "type" || key === "loc" || key === "range" || key === "isLocal") continue;
		const value = node[key];
		if (value && typeof value === "object") walk(value, cb, node);
	}
}

/** Dotted path of a plain a.b.c chain, else null. */
function dottedPath(node) {
	const parts = [];
	let current = node;
	while (current && current.type === "MemberExpression") {
		if (!current.identifier || current.indexer !== ".") return null;
		parts.unshift(current.identifier.name);
		current = current.base;
	}
	if (!current || current.type !== "Identifier") return null;
	parts.unshift(current.name);
	return parts.join(".");
}

/** Base identifier of a member chain: draw.DropCacheAvatar -> the `draw` identifier. */
function baseIdentifier(node) {
	let current = node;
	while (current && current.type === "MemberExpression") current = current.base;
	return current && current.type === "Identifier" ? current : null;
}

const HOOK_ACTIONS = { Add: true, Remove: true, Run: true, Call: true };

/**
 * Facts gathered from one file:
 *   hooksAdded / hooksUsed   hook names registered / called, with line numbers
 *   libRefs                  "lib.member" references used (not definitions)
 *   definedMembers           "lib.member" the file assigns to (library extensions)
 *   calledGlobals            identifiers used as a call target
 *   definedGlobals           globals the file assigns to or declares
 *   guarded                  "lib.member"/"name" the file nil-checks with `not`
 *   dynamicHooks             hook.Add/Run calls whose name is not a string literal
 *   parseError               the syntax error, if the file does not parse
 */
function collect(source, parser, knownLibs, wiki) {
	const facts = {
		hooksAdded: [], hooksUsed: [], libRefs: [], definedMembers: [], calledGlobals: [],
		definedGlobals: new Set(), guarded: new Set(), dynamicHooks: 0, parseError: null,
	};

	const recordLibraryMember = (variable) => {
		if (variable.type !== "MemberExpression" || variable.indexer !== ".") return;
		const base = baseIdentifier(variable);
		if (!base || base.isLocal !== false || !knownLibs.has(base.name)) return;
		facts.definedMembers.push(base.name + "." + variable.identifier.name);
	};

	const recordGlobal = (node) => {
		if (node.type === "Identifier") {
			if (node.isLocal === false) facts.definedGlobals.add(node.name);
		} else if (node.type === "MemberExpression") {
			const base = baseIdentifier(node);
			if (base && base.isLocal === false) facts.definedGlobals.add(base.name);
		}
	};

	let ast;
	try {
		ast = parser.parse(source, { comments: false, scope: true, locations: true, luaVersion: "5.1" });
	} catch (err) {
		facts.parseError = err;
		return facts;
	}

	const lineOf = (node) => (node.loc ? node.loc.start.line : 0);

	walk(
		ast,
		(node, parent) => {
			if (node.type === "AssignmentStatement") {
				for (const variable of node.variables) {
					recordGlobal(variable);
					recordLibraryMember(variable);
				}
			}

			if (node.type === "FunctionDeclaration" && node.identifier) {
				recordGlobal(node.identifier);
				recordLibraryMember(node.identifier);
			}

			// deliberate feature detection: `not X` or `if not a.b then`
			if (node.type === "UnaryExpression" && node.operator === "not" && node.argument) {
				if (node.argument.type === "Identifier") facts.guarded.add(node.argument.name);
				else {
					const target = dottedPath(node.argument);
					if (target) facts.guarded.add(target);
				}
			}

			// hook usage: hook.Add / hook.Remove / hook.Run / hook.Call
			const full = dottedPath(node);
			if (full && full.indexOf("hook.") === 0) {
				const action = full.slice(5);
				if (HOOK_ACTIONS[action]) {
					const call = parent && parent.type === "CallExpression" ? parent : null;
					const first = call && call.arguments && call.arguments[0];
					if (first && first.type === "StringLiteral") {
						const record = { name: first.value, line: lineOf(node), action };
						facts.hooksUsed.push(record);
						if (action === "Add") facts.hooksAdded.push(record);
					} else {
						facts.dynamicHooks++;
					}
				}
			}

			// library member references (the definitions above are skipped separately)
			if (node.type === "MemberExpression" && node.identifier && node.indexer === ".") {
				const base = baseIdentifier(node);
				if (base && base.isLocal === false && knownLibs.has(base.name)) {
					facts.libRefs.push({ path: base.name + "." + node.identifier.name, line: lineOf(node), node });
				}
			}

			// called globals
			if (node.type === "CallExpression" && node.base && node.base.type === "Identifier" && node.base.isLocal === false) {
				facts.calledGlobals.push({ name: node.base.name, line: lineOf(node) });
			}
		},
		null
	);

	return facts;
}

// --------------------------------------------------------------------------------------
// 3. whitelists: the wiki database, then TTT2 as a second source of truth
// --------------------------------------------------------------------------------------

function buildKnowledge(wiki) {
	const libraryMembers = new Map();
	const globals = new Set([
		"assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable", "ipairs", "load",
		"loadfile", "loadstring", "module", "newproxy", "next", "pairs", "pcall", "print", "rawequal",
		"rawget", "rawset", "require", "select", "setfenv", "setmetatable", "tonumber", "tostring",
		"type", "unpack", "xpcall", "_G", "_VERSION", "coroutine", "debug", "io", "math", "os",
		"package", "string", "table", "bit", "jit", "utf8", "arg", "_LOADED", "_REQUIRED",
		"CLIENT", "SERVER", "GM", "GAMEMODE", "LIST", "NULL",
	]);
	const hooks = new Map();

	if (!wiki) return { libraryMembers, globals, hooks };

	for (const [lib, data] of Object.entries(wiki.LIBRARIES || {})) {
		libraryMembers.set(lib, new Set(Object.keys((data && data.MEMBERS) || {})));
	}
	for (const [cls, data] of Object.entries(wiki.CLASSES || {})) {
		if (!libraryMembers.has(cls)) libraryMembers.set(cls, new Set(Object.keys((data && data.MEMBERS) || {})));
	}
	for (const kind of ["GLOBALS", "LIBRARIES", "CLASSES", "PANELS"]) {
		for (const name of Object.keys(wiki[kind] || {})) globals.add(name);
	}
	for (const [enumName, data] of Object.entries(wiki.ENUMS || {})) {
		globals.add(enumName);
		for (const member of Object.keys((data && data.MEMBERS) || {})) globals.add(member);
	}
	for (const [type, hookType] of Object.entries(wiki.HOOKS || {})) {
		for (const name of Object.keys((hookType && hookType.MEMBERS) || {})) hooks.set(name, "wiki:" + type);
	}

	return { libraryMembers, globals, hooks };
}

function absorbTtt2(knowledge, parser) {
	const files = luaFiles(TTT2_DIR);
	for (const file of files) {
		const facts = collect(fs.readFileSync(file, "utf8"), parser, knowledge.libraryMembers, null);
		if (facts.parseError) continue;

		for (const hook of facts.hooksUsed) if (!knowledge.hooks.has(hook.name)) knowledge.hooks.set(hook.name, "TTT2");
		for (const name of facts.definedMembers) {
			const [lib, member] = name.split(".");
			if (knowledge.libraryMembers.has(lib)) knowledge.libraryMembers.get(lib).add(member);
		}
		for (const ref of facts.libRefs) {
			const [lib, member] = ref.path.split(".");
			const members = knowledge.libraryMembers.get(lib);
			if (members) members.add(member);
		}
		for (const name of facts.definedGlobals) knowledge.globals.add(name);
	}
	return files.length;
}

// --------------------------------------------------------------------------------------
// 4. run
// --------------------------------------------------------------------------------------

function main() {
	const extension = findExtension();
	if (!extension) {
		console.error('Could not find the "GLua Enhanced" extension (venner.vscode-glua-enhanced).');
		console.error("Install it and reload, or point the script at a non-default extensions folder.");
		process.exit(2);
	}

	let parser;
	try {
		parser = loadParser(extension);
	} catch (err) {
		console.error("Could not recover the GLua parser: " + err.message);
		process.exit(2);
	}

	const wiki = extension.wiki ? JSON.parse(fs.readFileSync(extension.wiki, "utf8")) : null;
	const knowledge = buildKnowledge(wiki);
	const ttt2Count = absorbTtt2(knowledge, parser);

	console.log("glua-check - parser + wiki from " + path.basename(extension.dir));
	console.log(
		"  wiki data: " +
			(wiki
				? knowledge.hooks.size +
					" hooks, " +
					Object.keys(wiki.GLOBALS || {}).length +
					" globals, " +
					knowledge.libraryMembers.size +
					" libraries/classes"
				: "MISSING - API checks disabled") +
			" | TTT2 reference: " +
			ttt2Count +
			" files"
	);

	// ---- pass 1: read everything ------------------------------------------------------
	const sources = [];
	const allAdded = new Set();

	for (const file of luaFiles(LUA_DIR)) {
		const relative = path.relative(ADDON_ROOT, file).replace(/\\/g, "/");
		const facts = collect(fs.readFileSync(file, "utf8"), parser, knowledge.libraryMembers, wiki);
		sources.push({ relative, facts });
		for (const hook of facts.hooksAdded) allAdded.add(hook.name);
	}

	// ---- pass 2: evaluate -------------------------------------------------------------
	const syntax = [];
	const unknownHooks = [];
	const apiFailures = [];
	const apiNotes = new Map(); // "file path" -> one note per distinct reference
	const unlistened = new Map();
	const extensionPoints = new Set();
	const dynamic = [];

	for (const { relative, facts } of sources) {
		if (facts.parseError) {
			syntax.push(relative + " -> " + facts.parseError.message);
			continue;
		}
		if (facts.dynamicHooks) dynamic.push(relative + " (" + facts.dynamicHooks + ")");

		for (const hook of facts.hooksUsed) {
			const line = relative + ":" + hook.line + "  " + hook.name;
			if (!knowledge.hooks.has(hook.name) && !allAdded.has(hook.name)) {
				// this addon's own hooks are its public API, not typos
				if (hook.name.indexOf("TTTBots") === 0) extensionPoints.add(hook.name);
				else unknownHooks.push(line);
			}
			if (!allAdded.has(hook.name)) {
				if (!unlistened.has(hook.name)) unlistened.set(hook.name, []);
				unlistened.get(hook.name).push(line + " (" + hook.action + ")");
			}
		}

		const definedMembers = new Set(facts.definedMembers);
		for (const ref of facts.libRefs) {
			if (definedMembers.has(ref.path)) continue;
			const [lib, member] = ref.path.split(".");
			const members = knowledge.libraryMembers.get(lib);
			if (!members || members.has(member)) continue;
			const line = relative + ":" + ref.line + "  " + ref.path;
			const key = relative + " " + ref.path;
			if (facts.guarded.has(ref.path)) apiNotes.set(key, line + "   (nil-checked here)");
			else apiFailures.push(line);
		}

		for (const call of facts.calledGlobals) {
			if (knowledge.globals.has(call.name)) continue;
			if (facts.definedGlobals.has(call.name)) continue;
			if (/^(ROLE|TEAM|STATUS|SHOP|WEAPON|TRAIT|LANG|PERM|ROUND|WIN)_[A-Za-z0-9_]+$/.test(call.name)) continue;
			const line = relative + ":" + call.line + "  " + call.name + "(...)";
			const key = relative + " " + call.name;
			if (facts.guarded.has(call.name)) apiNotes.set(key, line + "   (nil-checked here)");
			else apiFailures.push(line);
		}
	}

	const section = (title, lines) => {
		console.log("\n=== " + title + ": " + (lines.length !== undefined ? lines.length : lines.size) + " ===");
		if (lines.length === undefined) lines = [...lines];
		for (const line of lines) console.log("  " + line);
	};

	section("syntax failures", syntax);
	section("unknown hook names", unknownHooks);
	section("API failures (reference to something that does not exist)", apiFailures);
	section("API notes (reference is nil-checked in the same file)", [...apiNotes.values()]);
	section(
		"hooks called but never registered in this tree",
		[...unlistened.entries()].map(([name, refs]) => name + "\n" + refs.map((r) => "       " + r).join("\n"))
	);
	if (extensionPoints.size) section("this addon's own extension points (TTTBots* hooks)", [...extensionPoints]);
	if (dynamic.length) section("dynamic hook names (cannot be checked)", dynamic);

	const failed = syntax.length + unknownHooks.length + apiFailures.length;
	console.log(
		"\n" + sources.length + " files checked | " + failed + " issue(s)" +
			(apiNotes.size ? ", " + apiNotes.size + " note(s)" : "")
	);
	process.exit(failed ? 1 : 0);
}

main();
