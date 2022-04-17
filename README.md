# command-completion.nvim

![Example screenshot](https://user-images.githubusercontent.com/46855713/163622605-30762e31-1ca8-4f94-9d7c-59d2889d8c89.png)

# Disclaimer

This plugin breaks things pretty severely if you `CTRL-F` from the command line into the cmdwin. Honestly any cmdwin usage and this could completely break. So . . . either don't do that, or wait until someone fixes the cmdwin upstream to play nice with floating windows & API functions etc. (which I plan on taking a stab at soon, but no promises).

# Requirements

* Neovim v0.7 or later

# Setup

1. Install `'smolck/command-completion.nvim'` with your favorite plugin manager.
2. Add `require('command-completion').setup()` to your `init.lua` (or `lua require('command-completion').setup()` to your `init.vim`).

# Options

Here's a list of the available configuration options with their defaults:
```lua
require('command-completion').setup {
    border = nil, -- What kind of border to use, passed through directly to `nvim_open_win()`,
                  -- see `:help nvim_open_win()` for available options (e.g. 'single', 'double', etc.)
    max_col_num = 5, -- Maximum number of columns to display in the completion window
    min_col_width = 20, -- Minimum width of completion window columns
    use_matchfuzzy = true, -- Whether or not to use `matchfuzzy()` (see `:help matchfuzzy()`) 
                           -- to order completion results
    highlight_selection = true, -- Whether or not to highlight the currently
                                -- selected item, not sure why this is an option tbh
    highlight_directories = true, -- Whether or not to higlight directories with
                                  -- the Directory highlight group (`:help hl-Directory`)
    tab_completion = true, -- Whether or not tab completion on displayed items is enabled
}
```

# Demo

https://user-images.githubusercontent.com/46855713/163624740-a7ce054d-2ff8-43ae-9145-d93a05dae074.mov

# Contributing

Contributions welcome! Just make a PR :D
