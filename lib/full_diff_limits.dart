const fullDiffTextByteLimit = 10 * 1024 * 1024;
const fullDiffTextLineLimit = 200000;

// A full-file patch can contain both valid file contents, one diff prefix byte
// for every row on both sides, and a bounded allowance for Git/path headers.
const fullDiffPatchByteLimit =
    2 * fullDiffTextByteLimit + 2 * fullDiffTextLineLimit + 64 * 1024;

// With full-file context Git emits at most both sides' rows plus its preamble
// and Hunk header. The allowance keeps malformed/unexpected output bounded.
const fullDiffPatchLineLimit = 2 * fullDiffTextLineLimit + 64;
