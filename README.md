![hi](https://en.wikipedia.org/wiki/Hi_(kana)#/media/File:Hiragana_%E3%81%B2_stroke_order_animation.gif)

**this is a work in progress!

bss - boring static site generator

+ Getting Started
	`VERBOSE=1` will make bss talkative.

	bss reads manifest.ini for configuration options:

	```
	[build]
	src=src/
	dest=_site/
	templates_dir=src/templates
	watch=false
	collections=posts
	exclude=*.md
	encoding=UTF-8
	[server]
	port=8090
	host=127.0.0.1

	```
	Please note the lack of quotes in values.

	Pages begin (as in Jekyll) with a YAML "front matter" block:  

	```
	---
	title: Nine Stories
	layout: default 
	meta:
	 - description
         - og:image
	draft: true
        author: J.D. Salinger 
	---
	```
	bss assumes template files use the `.tmpl` extention, which can be omitted.


A simple web server is included but one would be wise in using it only for local development purposes.

## TODO
- [] config is messy
- [] move some code into .pm files
- [] makefile.pl

