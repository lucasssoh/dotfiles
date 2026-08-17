-- jdtls config lives in lua/lsp/java.lua so it can also be started from a
-- background buffer by the warmup autocmd in lua/lsp/mason.lua (project
-- folder opened, no .java buffer touched yet).
require("lsp.java").start()
