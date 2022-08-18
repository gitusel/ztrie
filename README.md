# trie in Zig.

Inspired from Tsoding: https://gitlab.com/tsoding/trie and YouTube video: https://www.youtube.com/watch?v=2fosrL7I7oc&t=3348s

Using allocators and stacks.

## Quick Start

### Build

```console
$ ./build.sh
```
### Dump the Trie as SVG (Requires [Graphviz](https://graphviz.org/))

```console
$ ./zig-out/bin/ztrie dot
```

Open svg file using a web browser.


### Autocomplete prefix

```console
$ ./zig-out/bin/ztrie complete Ap
```

## References

- https://en.wikipedia.org/wiki/Trie

