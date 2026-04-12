# bss Example Sites

Ready-to-use starter templates for bss. Copy any folder, run `bss build -s`, and go.

## Templates

| Example | Description | Collections |
|---------|-------------|-------------|
| **blog/** | Classic blog with post listing, header/footer partials | `posts` |
| **portfolio/** | Project showcase with card grid layout | `projects` |
| **minimal/** | Single-page site, no partials, ~30 lines | none |
| **wiki/** | Sidebar navigation with page collection | `pages` |
| **photoblog/** | Image gallery grid layout | `photos` |
| **resume/** | Single-page CV/resume, clean print-friendly style | none |

## Quick Start

```sh
cp -r examples/blog mysite
cd mysite
bss build -s
# open http://localhost:9000
```

## Template Tips

### Listing collection items (the right way)

One loop, one item per iteration:

```tt
[% FOREACH c = collections.posts.sort.reverse %]
    <p><a href="posts/[% c %]">[% c.replace('(-|_|\.html|[0-9])', ' ') %]</a></p>
[% END %]
```

**Do NOT nest** a second `FOREACH` inside the collection loop — that causes each item to appear twice.

### Using partials

Split header/footer into `partials/` and include them:

```tt
[% header = "partials/header.tmpl" %]
[% footer = "partials/footer.tmpl" %]
[% INCLUDE $header %]

<!-- your page content -->

[% INCLUDE $footer %]
```

### Rendering the page body

The markdown body is passed as an array. Iterate it:

```tt
[% FOREACH part IN body %]
    [% part %]
[% END %]
```
