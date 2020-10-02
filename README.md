![hi](https://upload.wikimedia.org/wikipedia/commons/3/36/%E3%81%B2_%E6%95%99%E7%A7%91%E6%9B%B8%E4%BD%93.svg)

**this is a work in progress!**

bss - boring static site generator

+ Getting Started

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
	bss assumes template files use the `.tmpl` extention, which can be omitted. (Will probably have to change)


A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set, like so:

```
 BSS_DOCROOT=/path/to/your/_site/ bss --server
```

## TODO
- [x] move some code into .pm files
- [] makefile.pl
- [] meta tags
- [x] server command line flag
- [] watch command line flag

