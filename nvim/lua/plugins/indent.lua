-- Turn off the animated scope line in snacks.indent. The indent guides
-- themselves stay; only the animation that slides/grows the highlighted
-- scope when the cursor crosses block boundaries is disabled.
return {
  {
    "folke/snacks.nvim",
    opts = {
      indent = {
        animate = { enabled = false },
      },
    },
  },
}
