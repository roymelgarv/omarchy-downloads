// Pure logic for the Downloads plugin. No Qt or Node APIs here: this file is
// imported both by QML (`import "Model.js" as Model`) and by the Node test
// suite (tests/model.test.mjs), which is what keeps the plugin's behavior
// unit-testable without a running shell.

var PARTIAL_SUFFIXES = [".part", ".crdownload", ".download"];

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

// Names present now (and complete) that weren't complete in the previous
// scan — either brand new files or partials that finished. Drives the bar
// icon badge.
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

// Success-toast copy for a completed quick action. Elided so a long file
// name can't stretch the banner; unknown actions render nothing (the caller
// simply skips showing a toast).
function actionToastMessage(action, name) {
  var label = elideMiddle(String(name || ""), 40);
  if (action === "trash") return "Moved \"" + label + "\" to trash";
  if (action === "copy") return "Copied \"" + label + "\" to clipboard";
  return "";
}

function elideMiddle(name, max) {
  var s = String(name);
  if (s.length <= max) return s;
  var keepEnd = Math.min(12, Math.floor((max - 1) / 2));
  var keepStart = max - 1 - keepEnd;
  return s.slice(0, keepStart) + "…" + s.slice(s.length - keepEnd);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    humanSize: humanSize,
    extOf: extOf,
    isPartialDownload: isPartialDownload,
    finalNameOf: finalNameOf,
    sortByMtimeDesc: sortByMtimeDesc,
    searchScore: searchScore,
    filterEntries: filterEntries,
    completedSince: completedSince,
    elideMiddle: elideMiddle,
    actionToastMessage: actionToastMessage
  };
}
