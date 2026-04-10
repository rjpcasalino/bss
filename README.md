**this is a work in progress!**

# bss - boring static site generator

A boring (and simple...) static site generator written in Perl with a little help from rsync.

## Getting Started

bss reads manifest.ini for its configuration options:
	
	[build]
	src=/the/path/to/your/site/src/
	dest=/home/you/websites/_site/
	templates=src/templates
	collections=posts
	exclude=*.md,*.markdown,templates,junk
	encoding=UTF-8
	evaluate perl=0 # use perl false boolen value; this only works on template files
	[server]
	port=8090

Pages begin (as in Jekyll) with a YAML "front matter" block:  

	---
	title: Nine Stories
	layout: default 
        author: J.D. Salinger 
	---
		A Perfect Day for Bananafish wherein Seymour ends his own life.

Template file types can be any of: `.tmpl, .template, .html, .tt, .tt2`.

See: http://www.template-toolkit.org/index.html

One can define partials and such for use in templates or layouts or what have you:
```
[% footer = 'partials/footer.tt' %]
[% INCLUDE $footer %]
```

A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set.

An example:

```
$ BSS_DOCROOT=/path/to/your/_site bss build --server
# otherwise defaults to "_site"
```

Short flags are available: `-s` for `--server`, `-v` for `--verbose`, `-h` for `--help`.

#### build with nix
```
$ nix build --extra-experimental-features nix-command --extra-experimental-features flakes

# this will place bss in your nix profile so it's "installed" in a sense. This is the replacement for nix-env

$ nix profile --extra-experimental-features nix-command --extra-experimental-features flakes install

# or just
$ nix build
# and copy the result/bin/bss to run/wrappers/bin
# this won't survive a reboot.
```

## Known Issues
- [ ] Build can be slow on low-power hardware (~13s on 900MHz Intel); template processing is the bottleneck
- [ ] Collection discovery only picks up `.md`/`.markdown` extensions
- [ ] Template directory matching uses a simple regex that may match unintended paths

## Code Review Notes

A frank review of the codebase as of this commit:

**Bugs fixed in this branch:**
- `lookup_file` in Web.pm was missing its final `return` statement — the function would always return `undef`
- MIME types for GIF and JPEG were `text/gif` and `text/jpeg` instead of `image/gif` and `image/jpeg`
- Path traversal regex used `\\.` (literal backslash + any char) instead of `\.\.` (two literal dots)
- YAML front matter was being stripped line-by-line in `write_html`, which never actually matched the multi-line block; now stripped properly before markdown conversion
- `undef $/` permanently clobbered the global input record separator; now `local $/`
- `next` was used inside `find()` callbacks (which are subs, not loops); changed to `return`
- Operator precedence bug: `do_build() if ... or die` — the `or` binds more loosely than `and`, causing `die` to always execute on non-build commands
- `mkdir DEST` was immediately followed by `rm -rf DEST` — the mkdir was pointless, and the rm deleted user content; removed the rm
- HTML typo `<.p>` in redirect response
- `.git_ignore` renamed to `.gitignore` so Git actually reads it

**Remaining observations:**
- `no warnings "uninitialized"` is still active globally — this masks real bugs. Variables should be checked with `defined()` or `//` where needed.
- The `server` sub uses `fork()` without reaping children properly (now restored SIGCHLD handler).
- There are no tests. Even basic tests for YAML parsing, markdown conversion, and the web server would catch regressions.
- `system "rsync"` is called without checking the return value.
- `EVAL_PERL` in Template Toolkit config is a security risk if users process untrusted templates.
- The `find()` + `rsync` build pipeline is fragile: files are converted in-place in `SRC` then rsync'd to `DEST`, then the HTML files are deleted from `SRC`. If the process is interrupted, `SRC` is left dirty.
- `Web.pm` uses `Exporter` with `@ISA` instead of `use parent 'Exporter'`.
