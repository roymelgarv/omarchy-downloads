// Pure logic for the Downloads plugin. No Qt or Node APIs here: this file is
// imported both by QML (`import "Model.js" as Model`) and by the Node test
// suite (tests/model.test.mjs), which is what keeps the plugin's behavior
// unit-testable without a running shell.

var PARTIAL_SUFFIXES = [".part", ".crdownload", ".download"];
var IMAGE_EXTENSIONS = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "avif"];

function humanSize(bytes) {
  var n = Number(bytes);
  if (!isFinite(n) || n < 0) n = 0;
  var units = ["B", "KB", "MB", "GB", "TB"];
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  var text = i === 0 ? String(Math.round(n)) : n.toFixed(1).replace(/\.0$/, "");
  return text + " " + units[i];
}

function extOf(name) {
  var at = String(name).lastIndexOf(".");
  if (at <= 0) return ""; // no dot, or dotfile like ".bashrc"
  return String(name).slice(at + 1).toLowerCase();
}

function baseName(name) {
  var s = String(name);
  var at = s.lastIndexOf(".");
  if (at <= 0) return s; // no dot, or dotfile like ".bashrc"
  return s.slice(0, at);
}

function isImageExt(ext) {
  return IMAGE_EXTENSIONS.indexOf(String(ext).toLowerCase()) !== -1;
}

function partialSuffixOf(name) {
  var lower = String(name).toLowerCase();
  for (var i = 0; i < PARTIAL_SUFFIXES.length; i++) {
    if (lower.length > PARTIAL_SUFFIXES[i].length && lower.slice(-PARTIAL_SUFFIXES[i].length) === PARTIAL_SUFFIXES[i])
      return PARTIAL_SUFFIXES[i];
  }
  return "";
}

function isPartialDownload(name) {
  return partialSuffixOf(name) !== "";
}

function finalNameOf(name) {
  var suffix = partialSuffixOf(name);
  return suffix === "" ? String(name) : String(name).slice(0, -suffix.length);
}

function sortByMtimeDesc(entries) {
  return entries.slice().sort(function (a, b) {
    if (b.mtime !== a.mtime) return b.mtime - a.mtime;
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
  });
}

// Lower score = better match. -1 = no match.
function searchScore(query, name) {
  var q = String(query).toLowerCase();
  var n = String(name).toLowerCase();
  var at = n.indexOf(q);
  if (at === 0) return 0;
  if (at > 0) return 1;
  // subsequence: every query char appears in order
  var j = 0;
  for (var i = 0; i < n.length && j < q.length; i++) {
    if (n[i] === q[j]) j++;
  }
  return j === q.length ? 2 : -1;
}

function filterEntries(query, entries) {
  var q = String(query || "").trim();
  if (q === "") return sortByMtimeDesc(entries);
  var scored = [];
  for (var i = 0; i < entries.length; i++) {
    var score = searchScore(q, entries[i].name);
    if (score >= 0) scored.push({ entry: entries[i], score: score });
  }
  scored.sort(function (a, b) {
    if (a.score !== b.score) return a.score - b.score;
    return b.entry.mtime - a.entry.mtime;
  });
  return scored.map(function (s) { return s.entry; });
}

// Some browsers (observed with Chrome) reserve the final destination name as
// a 0-byte placeholder file while the real bytes land in a separately named
// partial file, only replacing the placeholder once the download finishes.
// Deleting that placeholder mid-download can break the browser's ability to
// finish the download, so it must never be shown as a normal, actionable
// row. We can't reliably derive the placeholder's exact name from the
// partial file's name (temp-naming schemes vary and can insert random
// tokens), so instead: whenever anything is downloading, treat any other
// zero-byte file as a likely placeholder and hide it.
function withoutDownloadPlaceholders(entries) {
  var anyDownloading = entries.some(function (e) { return e.partial === true; });
  if (!anyDownloading) return entries;
  return entries.filter(function (e) { return e.partial === true || e.size !== 0; });
}

function completedSince(prevNames, currentNames) {
  var prev = {};
  for (var i = 0; i < prevNames.length; i++) prev[prevNames[i]] = true;
  var out = [];
  for (var j = 0; j < currentNames.length; j++) {
    var name = currentNames[j];
    if (isPartialDownload(name)) continue;
    if (!prev[name]) out.push(name);
  }
  return out;
}

// Full name is kept, not elided — the toast banner wraps instead of hiding
// part of the name.
function actionToastMessage(action, name) {
  var label = String(name || "");
  if (action === "trash") return "Moved \"" + label + "\" to trash";
  if (action === "copy") return "Copied \"" + label + "\" to clipboard";
  return "";
}

function elideMiddle(name, max) {
  var s = String(name);
  if (s.length <= max) return s;
  // Below 4 chars there's no room for an ellipsis plus text on both sides;
  // just truncate from the start.
  if (max < 4) return s.slice(0, Math.max(0, max));
  var keepEnd = Math.min(12, Math.floor((max - 1) / 2));
  var keepStart = max - 1 - keepEnd;
  return s.slice(0, keepStart) + "…" + s.slice(s.length - keepEnd);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    humanSize: humanSize,
    extOf: extOf,
    isImageExt: isImageExt,
    baseName: baseName,
    isPartialDownload: isPartialDownload,
    finalNameOf: finalNameOf,
    sortByMtimeDesc: sortByMtimeDesc,
    searchScore: searchScore,
    filterEntries: filterEntries,
    withoutDownloadPlaceholders: withoutDownloadPlaceholders,
    completedSince: completedSince,
    elideMiddle: elideMiddle,
    actionToastMessage: actionToastMessage
  };
}
