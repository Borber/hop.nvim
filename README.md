# hop.nvim

> Neovim motions on speed! 

[![GitHub License](https://img.shields.io/github/license/wsdjeg/hop.nvim)](LICENSE)
[![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/wsdjeg/hop.nvim)](https://github.com/wsdjeg/hop.nvim/issues)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/wsdjeg/hop.nvim)](https://github.com/wsdjeg/hop.nvim/commits/master/)
[![GitHub Release](https://img.shields.io/github/v/release/wsdjeg/hop.nvim)](https://github.com/wsdjeg/hop.nvim/releases)
[![luarocks](https://img.shields.io/luarocks/v/wsdjeg/hop.nvim)](https://luarocks.org/modules/wsdjeg/hop.nvim)

**Hop** is an [EasyMotion](https://github.com/easymotion/vim-easymotion)-like plugin allowing you to jump anywhere in a
document with as few keystrokes as possible. It does so by annotating text in
your buffer with hints, short string sequences for which each character
represents a key to type to jump to the annotated text. Most of the time,
those sequences’ lengths will be between 1 to 3 characters, making every jump
target in your document reachable in a few keystrokes.

<p align="center">
  <img src="https://user-images.githubusercontent.com/506592/176885253-5f618593-77c5-4843-9101-a9de30f0a022.png"/>
</p>

<!-- vim-markdown-toc GFM -->

- [Features](#features)
- [Performance](#performance)
- [Installation](#installation)
    - [Using nvim-plug](#using-nvim-plug)
    - [Using lazy.nvim](#using-lazynvim)
    - [Using packer](#using-packer)
    - [Using luarocks](#using-luarocks)
    - [Supported Neovim versions](#supported-neovim-versions)
    - [Important note about versioning](#important-note-about-versioning)
- [Keybindings](#keybindings)
- [Other tools like hop.nvim](#other-tools-like-hopnvim)
- [Credits](#credits)
- [License](#license)

<!-- vim-markdown-toc -->

## Features

- Go to any word in the current buffer (`:HopWord`).
- Go to any camelCase word in the current buffer (`:HopCamelCase`).
- Go to any line and any line start (`:HopLine`, `:HopLineStart`).
- Go to anywhere (`:HopAnywhere`).
- Go to treesitter nodes (`:HopNodes`).
- Use Hop cross windows with multi-windows support (`:Hop*MW`).
- Use it with commands like `v`, `d`, `c`, `y` to visually select/delete/change/yank up to your new cursor position.
- Support a wide variety of user configuration options, among the possibility to alter the behavior of commands
  to hint only before or after the cursor (`:Hop*BC`, `:Hop*AC`), for the current line (`:Hop*CurrentLine`),
  change the dictionary keys to use for the labels, jump on sole occurrence, etc.
- Extensible: provide your own jump targets and create Hop extensions!

## Performance

Hop uses a compact jump pipeline designed to keep interactive latency low even with many visible targets:

- `HopLine` and `HopLineStart` use direct line target generators instead of going through regex matching.
- `HopWord`, `HopCamelCase`, and `HopAnywhere` scan buffer ranges directly, avoiding repeated Lua substring allocation while looking for matches.
- Hint labels are generated as compact prefix-free sequences, so nearby targets stay short without relying on a trie backtracking permutation pass.
- Key refinement uses a prefix index over the generated labels, narrowing candidates by prefix instead of scanning every hint after each key press.
- Extmarks are updated incrementally during refinement, so unmatched branches are removed without rebuilding every visible hint.

The main theoretical difference is that Hop now pays for the visible text and the active hint branch, not for repeatedly
rebuilding intermediate strings and hint sets. In the table below, `L` is the number of visible lines, `C` is the number
of visible characters, `T` is the number of generated targets, and `K` is the number of keys typed for a jump.

| Area | Previous shape | Current shape | Expected effect |
| --- | --- | --- | --- |
| `HopLine` / `HopLineStart` target generation | Generic regex-style target generation over line contexts. | Direct per-line target generation. | Lower constant cost; line jumps scale with `L` instead of paying regex machinery per line. |
| Word-like target generation | Repeatedly sliced Lua line suffixes before matching. Dense matches could allocate up to `O(C * T)` bytes, worst-case `O(C^2)` on a line. | Buffer-range matching against the original line range. | Near `O(C + T)` scanning behavior with far less allocation and GC pressure. |
| Hint label generation | Trie/backtracking permutation pass. | One compact prefix-free label pass. | Simpler `O(T)` label creation with shorter nearby labels and no permutation fallback path. |
| Key refinement | Filtered the active hints after each key press. | Prefix-index lookup for the typed label prefix. | From roughly `O(K * T)` refinement work to `O(K + active_branch)` lookup/update work. |
| Extmark updates | Rebuilt or rescanned larger hint sets during refinement. | Deletes unmatched extmarks and refreshes the surviving branch. | Less redraw work after every key press, especially when the first key removes most targets. |

Conclusion: the optimized implementation keeps the same user-facing purpose but removes the expensive general-purpose
paths from the hot loop. The largest theoretical win is in dense buffers, where word-like jumps avoid quadratic substring
allocation, and in large hint sets, where refinement no longer scans every hint after each key.

## Installation

### Using nvim-plug

```lua
require('plug').add({
  'wsdjeg/hop.nvim',
  opts = {
    keys = 'etovxqpdygfblzhckisuran',
  },
})
```

### Using lazy.nvim

```lua
{
    'wsdjeg/hop.nvim',
    version = "*",
    opts = {
        keys = 'etovxqpdygfblzhckisuran'
    }
}
```

### Using packer

```lua
use({
  'wsdjeg/hop.nvim',
  tag = '*', -- optional but strongly recommended
  config = function()
    -- you can configure Hop the way you like here; see :h hop-config
    require('hop').setup({ keys = 'etovxqpdygfblzhckisuran' })
  end,
})
```

### Using luarocks

```
luarocks install hop.nvim
```

### Supported Neovim versions

Hop supports **latest stable release** and nightly releases of Neovim. However, keep in mind that if you are on a nightly version, you must be **on
the last one**. If you are not, then you are exposed to compatibility issues / breakage.

### Important note about versioning

This plugin implements [SemVer] via git tags. Versions are prefixed with a `v`. You are **advised** to use a major version
dependency to be sure your config will not break when Hop gets updated.


## Keybindings

Hop doesn’t set any keybindings; you will have to define them by yourself.

If you want to create a key binding from within Lua:

```lua
-- place this in one of your configuration file(s)
local hop = require('hop')
local directions = require('hop.hint').HintDirection
vim.keymap.set('', '<leader>w', function()
  hop.hint_words({ direction = directions.AFTER_CURSOR })
end, {remap=true})
vim.keymap.set('', '<leader>W', function()
  hop.hint_words({ direction = directions.BEFORE_CURSOR })
end, {remap=true})
```


## Other tools like hop.nvim

* [sneak.nvim](https://github.com/justinmk/vim-sneak)
* [EasyMotion](https://github.com/easymotion/vim-easymotion)
* [Seek](https://github.com/goldfeld/vim-seek)
* [smalls](https://github.com/t9md/vim-smalls)
* [improvedft](https://github.com/chrisbra/improvedft)
* [clever-f](https://github.com/rhysd/clever-f.vim)
* [vim-extended-ft](https://github.com/svermeulen/vim-extended-ft)
* [Fanf,ingTastic;](https://github.com/dahu/vim-fanfingtastic)
* [IdeaVim-Sneak](https://plugins.jetbrains.com/plugin/15348-ideavim-sneak)
* [leap.nvim](https://github.com/ggandor/leap.nvim)
* [flash.nvim](https://github.com/folke/flash.nvim)

## Credits

- [smoka7's hop.nvim repo](https://github.com/smoka7/hop.nvim)

## License

This project is licensed under the GPL-3.0 License after commit 707049f.
