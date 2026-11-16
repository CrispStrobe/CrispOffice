# First consolidated qualification — retained evidence

This run measured saved Quds commit `35829317dc6d946244c96b2bf179f349853f1939`. All **875 selected tests passed**, formatting and whitespace passed, and source/harness fingerprints remained unchanged. Strict analysis found five issues: one test dynamic call, two missing loop blocks, one mutable test local, and one redundant non-null assertion. These were fixed without changing behavior before the final qualification.

The original runner output directory was named `final`; it was moved here without altering its logs or receipt so the subsequent final qualification could use that destination. The original output paths recorded in the receipt describe the execution location. This run is retained as development evidence and is **not added again** to final test totals. See the sibling `final/` receipt for the release gate.

`engine-tests.log` is stored losslessly as `engine-tests.log.gz`; the integrity index records its original hash, which matches the receipt. Decompress it to restore the recorded filename.
