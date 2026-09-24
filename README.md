# PixProSplitText 8.5.4

Splits one Pixelmator Pro text layer into any number of columns or rows, each
on its own layer, named `<original>_1 … <original>_n` and gathered into a group
with the original, which is kept and hidden. A header layer carrying the
layer's name is placed above the block, outside the group.

Original by Tim McCoy. Rewritten September 2026: the first version split on
line breaks, which put a whole wrapped paragraph into one column, and it edited
the original layer in place.
## Using it

1. Select a text layer, or run it with nothing selected and choose one from the
   list — each entry shows its word count. Hidden layers are not offered unless
   every text layer is hidden, in which case it offers to show one.
2. Confirm or change the layer's name. The pieces and the group are named after
   whatever you confirm.
3. Type how many pieces and press **Columns** or **Rows**.

The layer may be inside a group, at any depth; the pieces are made in the same
group.

## Formatting afterwards

**The pieces are ordinary text layers.** Justify them, change the font, size,
colour, line height or alignment, edit the wording — anything you would do to
any other text layer. Nothing about them depends on how they were made.

Justification is worth doing last. Splitting measures the text as it is set, so
changing the type afterwards reflows it within each piece; the division of the
words between pieces does not change.

## How the text is divided

Every piece gets the same number of lines, so the columns come out equal and
the last one holds the remainder — equal, or shorter, never longer. The script
measures a single word for the line height and the whole text for the total,
then fills each piece to that many lines, breaking only between words.

Because equal pieces matter more than fitting the space they came from, a block
whose text needs more room than the source layer had will run past it. Move the
group where it fits.

## Layout

Pieces are laid out inside the source layer's own box: columns divide its
width, rows divide its height, with a small gap between them. A layer wider
than the document, or hanging off its left edge, is brought back onto the
canvas. Height is not clamped.

Rows need a layer at least half the document's width — a column is too narrow
to divide into rows, whatever its proportions.

## Building

```
./build.sh
```

Compiles the script, installs the icon, restores the bundle identity that
`osacompile` drops, signs with Developer ID and installs to `/Applications`.
The version comes from `property scriptVersion` in the source.

The icon is built from the master artwork with `pixpro_icon SplitText`.

## Problems or suggestions

Open an issue: https://github.com/spurious-cox/pixprosplittext/issues
