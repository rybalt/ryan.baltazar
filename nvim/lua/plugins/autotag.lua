-- nvim-ts-autotag auto-closes paired tags (<div></div>) for tag-based
-- languages. LazyVim loads it on any file read; we constrain it to the
-- filetypes it actually supports so it stays dormant during C#/C++/Lua
-- sessions (i.e. ~always, on this machine).
--
-- Filetype list mirrors the plugin's own README:
-- https://github.com/windwp/nvim-ts-autotag
return {
  {
    "windwp/nvim-ts-autotag",
    ft = {
      "html",
      "xml",
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "jsx",
      "tsx",
      "vue",
      "svelte",
      "astro",
      "markdown",
      "php",
      "rescript",
      "handlebars",
      "hbs",
      "glimmer",
    },
  },
}
