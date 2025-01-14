# Single file

TODO: In the future I will migrate into a single file database like SQLite.

## FileVar

A FileVar is a single value but saved in a file. This have a Blok, a position, a size and a type.
For string, I will create something different I think, with a size max and a len, and can request more if needed.

## FileBlok

A blok is like memory but for file. It has a starting point and a size and can hold entities or FileVar.
Everything I will save will be linked into a Blok and I can create and delete it at will. The size it given in the config and can't change.

In SQLite, it is what they call a page I think. Similare thing.
