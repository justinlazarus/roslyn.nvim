test:
	nvim --headless -u tests/minimal_init.lua -c "lua require('tests.runner').run()"

.PHONY: test
