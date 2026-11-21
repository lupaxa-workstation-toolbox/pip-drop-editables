.PHONY: check test

test:
	/bin/bash tests/run_all.sh

check:
	/bin/bash -n src/pip-drop-editables
	/bin/bash tests/run_all.sh
