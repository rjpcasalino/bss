**this is a work in progress!**

# bss - boring static site generator

A boring (and simple...) static site generator written in Perl with a little help from rsync.

## Getting Started

	bss reads manifest.ini for its configuration options:
	
        ```
	[build]
	src=/the/path/to/your/site/src/
	dest=/home/you/websites/_site/
	templates=src/templates
	collections=posts
	exclude=*.md,*.markdown,templates,junk
	encoding=UTF-8
	[server]
	port=8090
	```

Pages begin (as in Jekyll) with a YAML "front matter" block:  

	```
	---
	title: Nine Stories
	layout: default 
        author: J.D. Salinger 
	---
	[% footer = 'partials/footer.tt' %]

		A perfect day for banana fish wherein Seymour ends his own life...

	[% INCLUDE $footer %]
	```

Template file types can be any of: `.tmpl, .template, .html, .tt, .tt2`.

A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set.

An example:

```
$ BSS_DOCROOT=/path/to/your/_site bss build --server
```

## FIXME
- [] BSS_DOCROOT should set to whatever is in config
- [] Handle removing YAML block correctly
- [] So that we can actually write OG daringfireball md
- [] Markdown parser might be garbage 
- [] short flags so we can do -v and -s for verbose and server
