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
	evaluate perl=0 # use perl false boolen value
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

#### build with nix
```
$ nix build --extra-experimental-features nix-command --extra-experimental-features flakes
# this will place bss in your nix profile so it's "installed" in a sense. This is the replacement for nix-env...
$ nix profile --extra-experimental-features nix-command --extra-experimental-features flakes install
```

## FIXME
- [] Handle removing YAML block correctly
- [] short flags so we can do -v and -s for verbose and server
