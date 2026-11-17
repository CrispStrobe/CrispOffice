# Frozen metadata and decoder oracle

`proofbird_metadata.json.gz` contains only the twelve small source/metadata and
license files from Proofbird `gector-bert-de` revision
`8e3b50beef7d775cedb7b876009e88bcf2e8d6af`; **no model weights**. Its JSON maps
basenames to base64 original bytes. Each file is checked against the same
immutable size/SHA-256 pins as the runtime bundle loader. The source license and
notice are included in the payload and in the package's `third_party` directory.

`decoder_oracle.json` retains 30 frozen source cases and 40 original passes:
prepared words, exact token IDs/first-subword alignment, selected original tags,
final corrections and original UTF-16 edits. It was reduced without changing
values from the Quds reference exporter at the same pinned model. The full
reference's SHA-256 is recorded inside the file. Ordinary tests replay the
selected labels with synthetic decisive logits; this independently tests the
Dart tokenizer, transforms, iterative edits and source alignment. It is **not a
native inference or raw-logit numerical test**. The separate
`tool/replay_reference.dart` authenticates and replays the original raw logits.

`tokenizer_oracle.json` contains 28 independently generated cases from the
frozen `tokenizer.json` using the reference environment's `tokenizers==0.22.1`.
Each case retains the supplied words, exact IDs and first-subword positions.
Cases include German case/accents, decomposed characters, emoji and ZWJ, Chinese
characters, controls and private-use scalars, embedded special tokens, long
words, and several other scripts. A word removed entirely by normalization is
recorded with `missing_word: true`; the Dart API deliberately rejects that
alignment instead of silently pairing subsequent words with the wrong tags.
