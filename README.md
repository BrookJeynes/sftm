<h1 align="center">
    sftm
</h1>

<div align="center">Single-faced Terminal Multiplexer</div>

<br>

**sftm** is a small-scoped unix single-faced terminal multiplexer built around 
a workflow of single screen usage. That is to say, only a single terminal occupies 
the screen at any given moment.

## Install
To install sftm, check the "Releases" section in Github and download the 
appropriate version or build locally via `zig build -Doptimize=ReleaseSafe`.

## Running
Currently, there is an issue with the underlying library being used and debug
output is printed to the terminal. This overwrites what's being rendered on the
screen. The simple fix is to redirect output to `/dev/null`.

```bash
./sftm 2>/dev/null
```

## Keybinds
All normal mode keybinds are prefixed with `<CTRL-a>`.

```
Normal mode:
q           :Exit.

c           :Create new terminal.
x           :Close terminal.
;           :Browse / search terminals. Will enter input mode.

]           :Go to next terminal.
[           :Go to previous terminal.

Input mode:
<Esc>              :Cancel input.
<Enter>            :Confirm input.
<Down>             :Scroll down.
<Up>               :Scroll up.
```

## Contributing
Contributions, issues, and feature requests are always welcome! This project is
currently using the latest stable release of Zig (0.13.0).
