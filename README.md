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
- [ ] Collection discovery only picks up `.md`/`.markdown` extensions
- [ ] If the template directory is under `SRC`, the post-build HTML cleanup may delete template `.html` files
- [ ] `system "rsync"` failure is warned but does not abort the build

## Code Review Notes

A frank review of the codebase by Claude Opus:

**Bugs fixed:**
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
- Template directory pruning used `$_ =~ /$config{TT_DIR}/` which compared a basename against an absolute path — never matched; fixed to use `abs_path($File::Find::name)`
- `no warnings "uninitialized"` removed — proper `//` defaults added for `$yaml->{title}`, `$yaml->{layout}`, and `$config{COLLECTIONS}`
- Image extension regex had operator precedence bug (`\.png|\.jpg|...` — only last alternative was anchored); fixed to `\.(png|jpe?g|gif|svg)$`
- `\&build(%config)` in wanted callback — unnecessary reference operator removed
- `$config{COLLECTIONS} = \%collections` was inside the for loop; moved outside

**Performance improvements:**
- Template lookup in `write_html` previously ran `find()` over the template directory for every markdown file processed. Replaced with a one-time pre-scan that builds a `%template_map` hash, reducing build time from O(n×m) to O(n+m) where n=files and m=templates.
- MIME type hash in Web.pm moved from per-request allocation to package-level declaration.

**Security notes:**
- `EVAL_PERL` in Template Toolkit config allows arbitrary Perl execution — documented the risk with an inline comment. Disabled by default (`// 0`).
- `rsync` exit status is now checked and warned on failure.

**Remaining observations:**
- There are no tests. Even basic tests for YAML parsing, markdown conversion, and the web server would catch regressions.
- The `find()` + `rsync` build pipeline is fragile: files are converted in-place in `SRC` then rsync'd to `DEST`, then the HTML files are deleted from `SRC`. If the process is interrupted, `SRC` is left dirty.
