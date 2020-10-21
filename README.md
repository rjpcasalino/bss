**this is a work in progress!**

# bss - boring static site generator

## Getting Started

	bss reads manifest.ini for its configuration options:

	```
	[build]
	src=/the/path/to/your/site/src/
	dest=/home/you/websites/_site/
	templates_dir=src/templates
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
	[% footer = 'partials/footer.tt' %]

	The meta tags will end up nowhere. Hasn't been implemented yet. :-)

	[% INCLUDE $footer %]
	```

	Template files can use any of the following file exts: `.tmpl, .template, .html, .tt, .tt2`.

A simple web server is included but one would be wise in using it only for local development purposes.
Ensure the `BSS_DOCROOT` ENV var is set, like so:

```
$ export BSS_DOCROOT=/path/to/your/_site/ 
$ bss --server
```

## TODO
- [] meta tags
- [] handle no flag and don't mkdir _site 

### Installing

I've been using [fatpack](https://metacpan.org/pod/distribution/App-FatPacker/bin/fatpack). Although, perl has myriad other options. 
See fatpack examples if you wish to install it.
