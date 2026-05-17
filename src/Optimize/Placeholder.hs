module Optimize.Placeholder
  ( optimize
  )
where

import IR.Core

optimize :: CoreProgram -> CoreProgram
optimize =
  -- TODO: Add equality saturation extraction and rewrite passes here.
  -- The Core IR is explicit and node-oriented so it can be translated into
  -- egglog relations without coupling egglog to parsing, typechecking, or eval.
  id
