# lispy-file-sink - the free music knowledge encyclopaedia

# Copyright © Josep Bigorra <jjbigorra@gmail.com>

# lispy-file-sink is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# lispy-file-sink is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with lispy-file-sink.  If not, see <https://www.gnu.org/licenses/>.

# Code:

# Constants

# System details
GUIX_VERSION := $(shell guix --version)

.PHONY: dev server production-server fmt init-db

# Logging helpers

define lispy-file-sink-log-info
	@printf "\n\033[1m[info] $(shell date --rfc-3339=seconds) - %s\033[0m\n" $(1)
endef


watchexec:
	watchexec -i "dist/**" -r -e scm,css,js -- "make server"

# Target to start a development server for lispy-file-sink
# Use watchexec to watch for file changes and restart the server on changes
dev:
	$(call lispy-file-sink-log-info,"starting development server for lispy-file-sink")
	make watchexec

# Target to start the lispy-file-sink server
# Start the server with the default configuration
server:
	$(call lispy-file-sink-log-info,"starting lispy-file-sink server")
	guix shell -m manifest.scm -- art work

# Target to start the lispy-file-sink server with production configuration
production-server:
	$(call lispy-file-sink-log-info,"starting production lispy-file-sink server")
	guix shell -m manifest.scm -- art work -c conf/production.conf

# Target to format source code files according to the style guide
# Find all .scm files and format them using 'guix style'
fmt:
	$(call lispy-file-sink-log-info,"formatting all Scheme files")
	find . -maxdepth 8 -name "*.scm" -type f -exec guix style -f {} \;

# Development REPL
repl:
	guix shell -m manifest.scm -- guile  \
		-L lib -L . \
		-c '((@ (ares server) run-nrepl-server))'

olive-css:
	curl --output "./pub/css/olive.min.css" \
		"https://codeberg.org/jjba23/olive-css/raw/branch/trunk/resources/css/olive.min.css"
