**this is a work in progress!**

# bss - boring static site generator

A dead simple static site generator written in Perl with a little help from rsync.

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

		foot clan
	[% INCLUDE $footer %]
	```

	Template files can use any of the following file exts: `.tmpl, .template, .html, .tt, .tt2`.

A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set.

An example:

```
$ BSS_DOCROOT=/path/to/your/_site bss build --server --watch
```

## FIXME (helpme) (todo)

- [] Handle removing YAML block correctly
- [] So that we can actually write OG daringfireball md

### Installing

I've been using [fatpack](https://metacpan.org/pod/App::FatPacker). This won't work with XS modules. So, this also needs to be fixed.
