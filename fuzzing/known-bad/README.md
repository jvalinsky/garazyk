# Known Bad Baseline

Crash signatures that have been triaged. New crashes matching any signature
listed below are suppressed by the harness. Signatures stay in this file; do
not move them to Git history comments or commit messages.

## Format

One signature per line, prefixed with `#` so naïve parsers can skip comments.
Signature shape: `<first 128 hex chars of crash artifact>_<byte size>`.

## File contents

The block below is the canonical baseline. Edit it in place. Parsers must
ignore `#`-prefixed lines.

```text
# This directory stores signatures of crashes that have been triaged.

# New crashes matching these signatures will be suppressed.

# Add crash signatures here after triage:

# Example format (first 128 hex chars + size):

# a1b2c3d4e5f60718293a1b2c3d4e5f60718293a1b2c3d4e5f60718293a1b2c3d4e5f60718293a1b2c3d4e5f60718293a1b2c3d4e5f60_1024

# null1dead2beef3cad4bed5caf6dad7eabed1dead2beef3cad4bed5caf6dad7eabed1dead2beef3cad4bed5caf6dad7eabed_512

# Empty baseline - start with no known-bad crashes

# As crashes are found and triaged, add their signatures here
```
