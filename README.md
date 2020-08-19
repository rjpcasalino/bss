![hi](https://en.wikipedia.org/wiki/Hi_(kana)#/media/File:Hiragana_%E3%81%B2_stroke_order_animation.gif)

*this is a work in progress!*

bss - boring static site generator

+ Getting Started
	VERBOSE=1 will make bss talkative.

	bss reads a manifest.ini for configuration options.

	```
	[build]
	src=src/
	dest=_site/
	templates_dir=templates
	watch=false

	include=
	exclude=*.md
	encoding=utf-8

	[server]
	port=1988
	host=127.0.0.1

	```
	Please note the lack of quotes in values.

A simple web server is included but one would be wise in using it only for local development purposes.

## TODO

- [X] Collections, or content or posts...
	- users need a way to enumerate over some list
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
