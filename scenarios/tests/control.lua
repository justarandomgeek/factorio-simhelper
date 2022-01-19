
if not script.active_mods["simhelper"] then
  error("simhelper is required to load this scenario.")
end

require("__simhelper__.scenario-scripts.tests.control")
