<p align="center">
  <a href="https://github.com/lupaxa-workstation-toolbox">
    <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/organisations/workstation-toolbox/readme-logo.png" alt="Workstation Toolbox" />
  </a>
</p>

<h1 align="center">Pip Drop Editables</h1>

An editable install stays satisfied, so `pip install -U` will not replace
it. This tool uninstalls that registration. The checkout stays on disk.
Dependencies stay installed. A package that is not editable is never
removed.

The installed program is one Bash script, `src/pip-drop-editables`. It
targets macOS Bash 3.2. Each chosen interpreter runs its own
`python -m pip`, with `--disable-pip-version-check`.

## Requirements

- Bash 3.2 (`/bin/bash` on macOS is enough)
- A Python 3 interpreter that has `pip`

`--check --index` uses that interpreter's Python standard library. It does
not need `curl`.

## Quick Start

Clone and run the script:

```bash
git clone git@github.com:lupaxa-workstation-toolbox/pip-drop-editables.git
cd pip-drop-editables
./src/pip-drop-editables --help
```

To put a checkout on `PATH`:

```bash
cp /path/to/pip-drop-editables/src/pip-drop-editables ~/bin/pip-drop-editables
chmod +x ~/bin/pip-drop-editables
```

Homebrew installs that same executable. After a stable release is published
in the tap:

```bash
brew tap the-lupaxa-project/tap
brew trust the-lupaxa-project/tap
brew install pip-drop-editables
```

## What it Does

Operands are package names. With none, every editable on the chosen Python
is in scope. Names are matched case-insensitively against the pip name.
The script looks only at the editable list. It does not search ordinary
installs.

```bash
pip-drop-editables --list
pip-drop-editables --check
pip-drop-editables --check --index
pip-drop-editables -n
pip-drop-editables -y --python-version 3.12 lupaxa-ssh-doctor
pip-drop-editables --all --purge-cache
```

| Invocation                   | What it does                                                          |
| ---------------------------- | --------------------------------------------------------------------- |
| `pip-drop-editables`         | Choose a Python if needed, list the editables, ask, then uninstall    |
| `pip-drop-editables pkg ...` | Limit the drop to those names                                         |
| `--list`                     | Print the editables and stop                                          |
| `--check`                    | Report which editables block `pip install -U`. Exit 1 when any do     |
| `--check --index`            | Also ask the package index for a published version                    |
| `-n`, `--dry-run`            | Show the drop and stop                                                |
| `-y`, `--yes`                | Skip the uninstall question                                           |
| `--purge-cache`              | After a real uninstall, run `pip cache purge` on each chosen Python   |
| `--python PATH`              | Use that interpreter, including a venv, and skip the version question |
| `--python-version 3.12`      | Use the installed 3.12 and skip the question                          |
| `--all`                      | Every installed Python on `PATH`, including pyenv installs            |
| `--version`                  | Print the tool version                                                |
| `--help`                     | Print usage and exit 0                                                |

`--list`, `--check`, and a drop do not combine. `--index` belongs only with
`--check`. `--purge-cache` does nothing on `--list`, `--check`, or
`--dry-run`. `--python`, `--python-version`, and `--all` do not combine.
`-y` does not choose a Python and does not skip that question.

A requested name that is not editable on any chosen interpreter exits 2
with `not an editable install` and uninstalls nothing. When several
interpreters are chosen, a name that is editable on only some of them is
removed only there.

The list is grouped by interpreter:

```text
Python: /opt/homebrew/bin/python3 (3.13.9)

Editable installs (1):

  lupaxa-ssh-doctor                          0.1.0
    /path/to/ssh-doctor
```

No editables prints `No editable installs.` and exits 0. On a real drop,
`--purge-cache` still purges in that case.

Uninstall is `python -m pip uninstall -y --disable-pip-version-check <name>`
on that package's interpreter. One real binary is uninstalled once, even
when two names on `PATH` point at it. A pip failure is counted, the
remaining names continue, and the process exits 1 at the end.
`--purge-cache` still runs after that loop.

On success the script prints `Removed editable installs.` and
`Checkouts on disk were not deleted. Dependencies were left installed.`
It then shows how to install a published release:

```bash
python -m pip install -U <name>
```

When the cache was not purged, it also says a just-published release can
still be hidden by the index cache, and shows
`python -m pip install -U --no-cache-dir <name>` and
`pip-drop-editables --purge-cache`.

## Choosing a Python

The script looks on `PATH` for `python3` and `python3.*` and keeps Python 3
only. Bare `python` is ignored. The same real binary counts once.
`current` is the first `python3` on `PATH`.

When that directory is a pyenv `shims` directory, each installed version
under the sibling `versions` directory is included too. A shim that pyenv
will not run, because that version is not selected, is skipped. The
install's own binary is listed and is what later runs `pip`. A shim and the
binary it dispatches to are one row. Named environments and directories
that contain `pyvenv.cfg` are not included.

A venv is not in that list. `--python PATH` selects one, including a venv
that is not on `PATH`, and skips the question.

When more than one Python is installed and the command has no `--python`,
`--python-version`, or `--all`, the script asks on `/dev/tty`:

```text
Pythons on PATH:

  current, 3.13  3.13.9   /Users/you/.pyenv/shims/python3
  3.12           3.12.12  /Users/you/.pyenv/versions/3.12.12/bin/python3

Which Python? [current]
```

- `current`, or an empty answer, is the first `python3`.
- A version is `major.minor` or `major.minor.patch`. `3.12` matches any `3.12.x`. `3.12.8` matches that version. A bare major such as `3` is rejected.
- `all` is every distinct interpreter, including pyenv installs.

When `current` and a versioned name are the same binary, one row lists
both labels. If a `major.minor` matches two binaries, the script exits 2
and tells you to pass `--python`. Any other answer, including end of file,
prints `Left in place.` and exits 0.

One installed Python is used without asking. If the terminal cannot be
opened and a question is still required, the script prints the versions
and exits 2.

## Check and Index

`--check` does not uninstall and does not purge the cache. Every editable
blocks `pip install -U` of that name. The report shows the interpreter,
the package name, the installed version, the checkout path, and
`blocks pip install -U`. Exit 0 when there are none. Exit 1 when there is
at least one.

`--check --index` then asks the package index, using that interpreter's
standard library. The index is `PIP_INDEX_URL` when set, otherwise
`https://pypi.org/simple`. One trailing slash is removed, then a slash and
the PEP 503 name are appended. The request sends
`Accept: application/vnd.pypi.simple.v1+json` and times out after 15
seconds.

The newest stable version is a dotted numeric release. A local `+suffix`
is ignored. Pre-release and development versions are ignored when any
stable release exists. `1.0` and `1.0.0` are equal. If nothing parses, the
package is reported as unparsed. A timeout or an index that does not
return that JSON is reported as `index: unavailable`. Other packages still
get a result. The local block line is printed either way. The editable
still blocks the upgrade when the published version is the same.

## Prompts

The Python question and the uninstall question are both read from
`/dev/tty`.

Uninstall asks once for the whole selection, including `--all`:

```text
Uninstall these N editable installs? [y/N]:
```

Only `y`, `Y`, `yes`, or `YES` proceeds. Any other answer, including end
of file, prints `Left in place.` and exits 0. `-y` skips this question.
`-n` prints `Dry run. Nothing uninstalled.` and does not ask.

Without a terminal, a required question exits 2. `-y`, `--python`,
`--python-version`, and `--all` are how a drop runs with no terminal.
`--list` and `--check` do not ask.

## Exit Codes

| Code | When                                                                                                    |
| ---- | ------------------------------------------------------------------------------------------------------- |
| 0    | Success, nothing to do, user cancelled, dry run, or a check that found no editables                     |
| 1    | An uninstall failed, a chosen interpreter has no `pip` module, or `--check` found at least one editable |
| 2    | Usage error                                                                                             |

Usage errors include an unknown flag, combining `--list`, `--check`, and a
drop, `--index` without `--check`, a missing `--python` path, a name that
is not an editable on any chosen interpreter, a `--python-version` that
matches nothing or two binaries, and a required question when `/dev/tty`
cannot be opened.

With `--all`, an interpreter whose `pip` module is missing is a failure
for that interpreter. The others still run. The process exits 1 if any
interpreter failed.

<a href="https://github.com/the-lupaxa-project">
  <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/components/footer-for-child-orgs.svg" alt="The Lupaxa Project Footer" width="100%" />
</a>
