# Portability demo — Claude package

This is a self-contained, vendored squad snapshot. Generation did not install or
enable anything, and using it does not require cheeky-squad-os to remain installed.

## Activate deliberately

Inspect it, then launch Claude Code with this directory via `--plugin-dir` for a
temporary activation. Use your approved plugin installation flow only if you want the
package to persist. Installation and enablement are intentionally separate from export.

Claude owns the shared runtime, so this package registers the vendored lifecycle hooks.

## Packaged roles

- `cheeky-portability-demo--evidence-reader`
- `cheeky-portability-demo--report-writer`

Export version: `1.1.0`
