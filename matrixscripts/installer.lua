if fs.exists("/matrixscripts/turtle") then
    fs.delete("/matrixscripts/turtle")
end
fs.makeDir("/matrixscripts/turtle/core")
fs.makeDir("/matrixscripts/turtle/miner")

shell.run("wget", "https://github.com/FeuerMatrix/computercraft-programs/raw/development/matrixscripts/miner/ExcavationTree.lua", "/matrixscripts/turtle/miner/ExcavationTree.lua")
shell.run("wget", "https://github.com/FeuerMatrix/computercraft-programs/raw/development/matrixscripts/miner/miner.lua", "/matrixscripts/turtle/miner/miner.lua")
shell.run("wget", "https://github.com/FeuerMatrix/computercraft-programs/raw/development/matrixscripts/core/term_core.lua", "/matrixscripts/turtle/core/term_core.lua")
shell.run("wget", "https://github.com/FeuerMatrix/computercraft-programs/raw/development/matrixscripts/core/turtle_core.lua", "/matrixscripts/turtle/core/turtle_core.lua")