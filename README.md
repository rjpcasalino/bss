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
	templates_dir=templates
	watch=false

	exclude=*.md
	encoding=UTF-8

	[server]
	port=1988
	host=127.0.0.1

	```
	Please note the lack of quotes in values.

	Pages begin (as in Jekyll) with a YAML "front matter" block:  

	``
	---
	title: Nine Stories
	layout: default 
	meta:
	 - not yet...
	draft: true
        author: J.D. Salinger 
	---
	```
	bss assumes template files use the `.tmpl` extention, which can be omitted.


A simple web server is included but one would be wise in using it only for local development purposes.

## TODO

- [X] Collections, or content or posts...
- [] use Jekyll regex for YAML (front matter) block
- [] replace all (^) with (/A) and all ($) with (/z) in regular expressions
- [] clean up how / what we consider collections
- [] lib/webserver
- [] handle images
- [] handle js
- [] tests
- [] make.pl 
- [] HTML tidy
	- for cleanup
- [] watch
	- dev has notify.pl
- [X] system call with params
- [] all the front matter block options :-/
