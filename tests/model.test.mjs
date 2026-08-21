import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Model = require("../Model.js");

// ---------------------------------------------------------------- humanSize

test("humanSize formats bytes below 1 KB as B", () => {
  assert.equal(Model.humanSize(0), "0 B");
  assert.equal(Model.humanSize(512), "512 B");
});

test("humanSize formats KB/MB/GB with one decimal, trimming .0", () => {
  assert.equal(Model.humanSize(2048), "2 KB");
  assert.equal(Model.humanSize(1536), "1.5 KB");
  assert.equal(Model.humanSize(2 * 1024 * 1024), "2 MB");
  assert.equal(Model.humanSize(25.4 * 1024 * 1024 * 1024), "25.4 GB");
});

test("humanSize handles invalid input as 0 B", () => {
  assert.equal(Model.humanSize(-5), "0 B");
  assert.equal(Model.humanSize(NaN), "0 B");
  assert.equal(Model.humanSize(undefined), "0 B");
});

// ---------------------------------------------------------------- extOf

test("extOf returns lowercase extension without the dot", () => {
  assert.equal(Model.extOf("photo.JPEG"), "jpeg");
  assert.equal(Model.extOf("archive.tar.gz"), "gz");
});

test("extOf returns empty string for files without extension or dotfiles", () => {
  assert.equal(Model.extOf("Makefile"), "");
  assert.equal(Model.extOf(".bashrc"), "");
});

// -------------------------------------------------------------- baseName

test("baseName strips the extension shown separately as the file's type", () => {
  assert.equal(Model.baseName("report.pdf"), "report");
  assert.equal(Model.baseName("archive.tar.gz"), "archive.tar");
});

test("baseName leaves files without an extension or dotfiles untouched", () => {
  assert.equal(Model.baseName("Makefile"), "Makefile");
  assert.equal(Model.baseName(".bashrc"), ".bashrc");
});

// ------------------------------------------------------- partial downloads

test("isPartialDownload detects browser partial-download suffixes", () => {
  assert.equal(Model.isPartialDownload("movie.mkv.part"), true);
  assert.equal(Model.isPartialDownload("setup.exe.crdownload"), true);
  assert.equal(Model.isPartialDownload("song.mp3.download"), true);
  assert.equal(Model.isPartialDownload("doc.pdf"), false);
  assert.equal(Model.isPartialDownload("partition-map.txt"), false);
});

test("finalNameOf strips the partial suffix", () => {
  assert.equal(Model.finalNameOf("movie.mkv.part"), "movie.mkv");
  assert.equal(Model.finalNameOf("setup.exe.crdownload"), "setup.exe");
  assert.equal(Model.finalNameOf("doc.pdf"), "doc.pdf");
});

// ---------------------------------------------------------------- sorting

test("sortByMtimeDesc orders newest first without mutating input", () => {
  const entries = [
    { name: "old.txt", mtime: 100 },
    { name: "new.txt", mtime: 300 },
    { name: "mid.txt", mtime: 200 }
  ];
  const sorted = Model.sortByMtimeDesc(entries);
  assert.deepEqual(sorted.map(e => e.name), ["new.txt", "mid.txt", "old.txt"]);
  assert.equal(entries[0].name, "old.txt");
});

test("sortByMtimeDesc breaks mtime ties by name for stable display", () => {
  const sorted = Model.sortByMtimeDesc([
    { name: "b.txt", mtime: 100 },
    { name: "a.txt", mtime: 100 }
  ]);
  assert.deepEqual(sorted.map(e => e.name), ["a.txt", "b.txt"]);
});

// ---------------------------------------------------------------- search

test("filterEntries returns newest-first entries when query is empty", () => {
  const entries = [
    { name: "old.txt", mtime: 100 },
    { name: "new.txt", mtime: 300 }
  ];
  const out = Model.filterEntries("", entries);
  assert.deepEqual(out.map(e => e.name), ["new.txt", "old.txt"]);
});

test("filterEntries matches case-insensitive substrings", () => {
  const entries = [
    { name: "Invoice-March.pdf", mtime: 1 },
    { name: "photo.jpg", mtime: 2 }
  ];
  const out = Model.filterEntries("invoice", entries);
  assert.deepEqual(out.map(e => e.name), ["Invoice-March.pdf"]);
});

test("filterEntries ranks name-start matches above mid-name matches", () => {
  const entries = [
    { name: "my-report.pdf", mtime: 5 },
    { name: "report.pdf", mtime: 1 }
  ];
  const out = Model.filterEntries("rep", entries);
  assert.deepEqual(out.map(e => e.name), ["report.pdf", "my-report.pdf"]);
});

test("filterEntries falls back to subsequence matching", () => {
  const entries = [
    { name: "quarterly-sales-2026.xlsx", mtime: 1 },
    { name: "notes.txt", mtime: 2 }
  ];
  const out = Model.filterEntries("qs26", entries);
  assert.deepEqual(out.map(e => e.name), ["quarterly-sales-2026.xlsx"]);
});

test("filterEntries breaks equal-rank ties by newest first", () => {
  const entries = [
    { name: "report-a.pdf", mtime: 1 },
    { name: "report-b.pdf", mtime: 9 }
  ];
  const out = Model.filterEntries("report", entries);
  assert.deepEqual(out.map(e => e.name), ["report-b.pdf", "report-a.pdf"]);
});

test("filterEntries returns empty array when nothing matches", () => {
  assert.deepEqual(Model.filterEntries("zzz", [{ name: "a.txt", mtime: 1 }]), []);
});

// ------------------------------------------------ download placeholders

test("withoutDownloadPlaceholders hides zero-byte files while something is downloading", () => {
  const entries = [
    { path: "/a", name: "a.crdownload", size: 1024, partial: true },
    { path: "/b", name: "a.tar.gz", size: 0, partial: false },
    { path: "/c", name: "c.txt", size: 500, partial: false }
  ];
  const out = Model.withoutDownloadPlaceholders(entries);
  assert.deepEqual(out.map(e => e.path), ["/a", "/c"]);
});

test("withoutDownloadPlaceholders keeps zero-byte files when nothing is downloading", () => {
  const entries = [{ path: "/a", name: "empty.txt", size: 0, partial: false }];
  assert.deepEqual(Model.withoutDownloadPlaceholders(entries), entries);
});

test("withoutDownloadPlaceholders never hides the partial entry itself, even at 0 bytes", () => {
  const entries = [{ path: "/a", name: "a.crdownload", size: 0, partial: true }];
  assert.deepEqual(Model.withoutDownloadPlaceholders(entries), entries);
});

// ------------------------------------------------------------ badge logic

test("completedSince reports files that appeared since the previous scan", () => {
  const prev = ["a.pdf"];
  const current = ["a.pdf", "b.iso"];
  assert.deepEqual(Model.completedSince(prev, current), ["b.iso"]);
});

test("completedSince counts a partial download that became final", () => {
  const prev = ["movie.mkv.part"];
  const current = ["movie.mkv"];
  assert.deepEqual(Model.completedSince(prev, current), ["movie.mkv"]);
});

test("completedSince ignores new in-progress partial files", () => {
  const prev = [];
  const current = ["movie.mkv.part"];
  assert.deepEqual(Model.completedSince(prev, current), []);
});

test("completedSince reports nothing when files are only removed", () => {
  assert.deepEqual(Model.completedSince(["a.pdf", "b.iso"], ["a.pdf"]), []);
});

// ------------------------------------------------------------ elideMiddle

test("elideMiddle leaves short names untouched", () => {
  assert.equal(Model.elideMiddle("short.txt", 20), "short.txt");
});

test("elideMiddle shortens long names in the middle, keeping the extension", () => {
  const out = Model.elideMiddle("a-very-long-download-file-name-from-somewhere.tar.gz", 30);
  assert.ok(out.length <= 30, `too long: ${out} (${out.length})`);
  assert.ok(out.includes("…"));
  assert.ok(out.endsWith("tar.gz"));
  assert.ok(out.startsWith("a-very"));
});

// ------------------------------------------------------ actionToastMessage

test("actionToastMessage formats a trash success message", () => {
  assert.equal(Model.actionToastMessage("trash", "report.pdf"), 'Moved "report.pdf" to trash');
});

test("actionToastMessage formats a copy success message", () => {
  assert.equal(Model.actionToastMessage("copy", "report.pdf"), 'Copied "report.pdf" to clipboard');
});

test("actionToastMessage keeps the full file name for a long name (banner wraps)", () => {
  const longName = "a-very-long-download-file-name-from-somewhere-important.tar.gz";
  const out = Model.actionToastMessage("trash", longName);
  assert.ok(out.includes(longName));
  assert.ok(!out.includes("…"));
});

test("actionToastMessage returns an empty string for an unknown action", () => {
  assert.equal(Model.actionToastMessage("rename", "report.pdf"), "");
});
