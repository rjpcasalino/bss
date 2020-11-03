**this is a work in progress!**

# bss - boring static site generator

## Getting Started

	bss reads manifest.ini for its configuration options:

	```
	[build]
	src=src/
	dest=_site/
	templates_dir=src/templates
	watch=false
	collections=posts
	exclude=*.md,*.markdown,templates,junk
	encoding=UTF-8
	[server]
	port=8090

	```
	Please note the lack of quotes in values.

	Pages begin (as in Jekyll) with a YAML "front matter" block:  

	```
	---
	title: Nine Stories
	layout: default 
	meta:
	 - description: A collection of short stories by American fiction writer J. D. Salinger published in 1953. 
         - og:image
	draft: true
        author: J.D. Salinger 
	---
	```
	Template files can use any of the following file exts: `.tmpl, .template, .html, .tt, .tt2`.

A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set, like so:

```
$ export BSS_DOCROOT=/path/to/your/_site/ 
$ bss build --server
```

## TODO
- [] meta tags
