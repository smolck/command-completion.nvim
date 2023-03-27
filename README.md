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
    total_rows = 3, -- count of rows in completion window
    total_columns = 5, -- count of columns in completion window
    use_matchfuzzy = true, -- Whether or not to use `matchfuzzy()` (see `:help matchfuzzy()`) 
                           -- to order completion results
    highlight_selection = true, -- Whether or not to highlight the currently
                                -- selected item, not sure why this is an option tbh
    highlight_directories = true, -- Whether or not to higlight directories with
                                  -- the Directory highlight group (`:help hl-Directory`)
    mapping_next = "<Tab>", –– set mapping for moving cursor to next item
    mapping_prev = "<S-Tab>", -- set mapping for moving cursor to previous item
    completion = true, -- Whether or not completion on displayed items is enabled
}
```

# Demo

https://user-images.githubusercontent.com/46855713/163624740-a7ce054d-2ff8-43ae-9145-d93a05dae074.mov

# Contributing

Contributions welcome! Just make a PR :D
