# Security

DevSweep deletes files, so a bug that makes it delete the wrong thing is
treated as a security issue here, not just a bug.

## What to report privately

- It deleted, or would delete, anything it shouldn't: something outside
  your home folder, through a symlink, in a folder git tracks, or anything
  the README's [Safety first](README.md#safety-first) says is never touched.
- It ran a tool (`simctl`, `brew`, `git`) on something it shouldn't, or in a
  way it shouldn't.
- Put Back put something back somewhere other than where it was.
- Anything else that could lose someone's data.

Plain bugs, like a wrong size, a screen that looks off, or a crash with
nothing lost, are welcome as public [issues](https://github.com/JaviLorbada/devsweep/issues).

## How

Use **Report a vulnerability** on the repository's
[Security tab](https://github.com/JaviLorbada/devsweep/security), so the
report stays private until it's fixed. Please include:

- DevSweep's version, from its About window or the release you downloaded,
  and your macOS version;
- what you did, and what was, or would have been, deleted;
- if you can, the output of `devsweep` on its own, which only reports and
  shows what it found.

## What happens next

You'll get a reply within a week. A confirmed problem is fixed in a new
release, with a line in the [CHANGELOG](CHANGELOG.md) and credit to you if
you'd like it. Only the latest release gets fixes.
