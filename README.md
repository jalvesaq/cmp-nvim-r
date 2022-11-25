# cmp-nvim-r


Completion source for [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) using [Nvim-R](https://github.com/jalvesaq/Nvim-R) as backend.


## Installation

Use a plugin manager such as [vim-plug](https://github.com/junegunn/vim-plug)
or [packer](https://github.com/wbthomason/packer.nvim).

## Setup

Register the source for `nvim-cmp`:

```lua
require'cmp'.setup {
  sources = {
    { name = 'cmp_nvim_r' },
  }
}
```

## Configuration

### cmp-nvim-r

`cmp-nvim-r` has two options:

  - `filetypes`: The list of file types for which the source should be enabled.
     (default: 'r', 'rmd', 'quarto', 'rnoweb', 'rhelp')

  - `doc_width`: The expected maximum width of the floating documentation
    window. This value is used to format the usage section of function
    documentation. Arguments are concatened, but line breaks are inserted
    between arguments before the line reaches the number of columns defined by
    `doc_width`. (default: 58)

    See also the option `maxwidth` in [lspkind.nvim](https://github.com/onsails/lspkind.nvim).

Below is an example of how to set theses options:

```lua
require'cmp_nvim_r'.setup({
  filetypes = {'r', 'rmd', 'quarto'},
  doc_width = 58
  })
```


### nvim-cmp

The source `cmp_nvim_r` does not require any special configuration of
`nvim-cmp` to work, and the same configuration does not work for everone.
Anyway, I share below what worked best for me:

  - `cmp-nvim-r` adds sets the field sortText of completed items as "0" for
    function arguments and "9" for everything else. This means that function
    arguments will always be at the top of the list of suggestions if you put
    `cmp.config.compare.sort_text` at the top of list of compare `nvim-cmp`
    functions.

  - Install a Nerd font and install and configure your terminal emulator to
    use it. Then install
    [lspkind.nvim](https://github.com/onsails/lspkind.nvim) to have symbols
    representing the kind of object whose name is being completed.

  - The names of kind of objects are generic names of the LSP server protocol
    and do not match the classes of R objects. So, it is better to hide the
    names and display only the symbols.

An example following the above suggestions:

```lua
cmp.setup({
    formatting = {
        fields = {'abbr', 'kind', 'menu'},
        format = lspkind.cmp_format({
            mode = 'symbol', -- show only symbol annotations
            maxwidth = 50, -- prevent the popup from showing more than provided characters
            ellipsis_char = '...', -- the truncated part when popup menu exceed maxwidth
            before = function(entry, item)
                local menu_icon = {
                    nvim_lsp = '',
                    vsnip = '',
                    path = '',
                    cmp_zotcite = 'z',
                    cmp_nvim_r = 'R'
                }
                item.menu = menu_icon[entry.source.name]
                return item
            end,
        })
    },
    sources = cmp.config.sources({
        { name = 'vsnip' },
        { name = 'cmp_zotcite' },
        { name = 'cmp_nvim_r' },
        { name = 'nvim_lsp' },
        { name = 'path', option = { trailing_slash = true } },
    }),
})
```

