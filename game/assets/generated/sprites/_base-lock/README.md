# Pixel Night Shift sprite base-lock staging

Status: awaiting human Base Lock. These files are candidate-generation inputs,
not runtime assets and not successful `sprite-gen` runs.

- Existing procedural PNGs are identity and pixel-density references only.
- `debugger` candidates use magenta chroma because cyan/green details are part
  of the subject.
- `broken_pixel` candidates use green chroma because red/orange details are
  part of the subject.
- Select exactly one candidate per asset in the Korean curation view, or reject
  the whole row. Do not create a component-row run until that decision is
  recorded.
- Accepted pilot runs will live in sibling folders `../debugger/` and
  `../broken_pixel/`. This staging folder must never be referenced by runtime
  code.
