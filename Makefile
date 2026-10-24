# chez-httparse canonical entry points.
#
# Development and CI both use these targets and the checked-in CMake presets.
# Windows has no make in the base install, so these are a convenience over the
# presets, never the only way in: `cmake --preset dev` and `ctest --preset pr`
# work identically everywhere.
#
# An empty selection is a failure, never a silent pass. That rule lives in the
# test presets themselves (execution.noTestsAction), not only here, or the
# preset path documented above would quietly accept what this path rejects --
# and the whole point of the paragraph above is that the two are equivalent.
# CTEST_FLAGS keeps --no-tests=error as well so an older CTest still refuses.

CMAKE ?= cmake
CTEST ?= ctest
CTEST_FLAGS ?= --output-on-failure --no-tests=error

# The docs site is rendered with chez-cmark-gfm, which is not a dependency of
# the library: name a checkout with CMARK_GFM_ROOT. These targets run Chez
# directly rather than through CMake, so the site builds on a distribution's
# Chez as well as on the version the library's own build requires. SITE_REF
# is the git ref that ../ links in docs/ are pinned to on GitHub.
CHEZ ?= chez
AKKU ?= akku
SITE_REF ?= main
SITE_LIBDIRS = .:test/site:test/support/harness:$(CMARK_GFM_ROOT)/src

# Bare 'make' prints the target list rather than building; 'make all' still builds.
.DEFAULT_GOAL := help

.PHONY: all help doctor configure build dev test test-all prod clean corpus-refresh parser-refresh site check-site cmark-gfm-root check-akku check-help

all: build   ## build the development preset

# 'help' prints every target that carries a '## ' description by scanning this
# Makefile itself, so the descriptions live beside the targets they document
# and cannot drift out of sync with them: add a target with a '## ' note and
# it appears here automatically.
help:   ## list these targets (shown when you run a bare 'make')
	@echo "chez-httparse make targets:"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z][a-zA-Z_-]*:.*## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "If discovery cannot find a runtime, point it at one explicitly:"
	@echo "  cmake --preset dev -DHTTPARSE_CHEZ_EXECUTABLE=/absolute/path/to/scheme"

# Configure is where discovery runs and where every toolchain diagnostic is
# emitted, so 'doctor' is just a configure whose output is the point.
doctor:   ## report the discovered Chez toolchain, then stop
	$(CMAKE) --preset dev

configure:   ## configure the development preset without building
	$(CMAKE) --preset dev

build: configure   ## configure and build the development preset
	$(CMAKE) --build --preset dev

dev: build   ## build, then run the harness and build-layer self-tests
	$(CTEST) --preset harness $(CTEST_FLAGS)

test: build   ## build, then run the pull-request selection
	$(CTEST) --preset pr $(CTEST_FLAGS)

test-all: build   ## build, then run the complete selection
	$(CTEST) --preset release $(CTEST_FLAGS)

prod:   ## configure and build the release preset
	$(CMAKE) --preset prod
	$(CMAKE) --build --preset prod

clean:   ## remove all build trees
	$(CMAKE) -E rm -rf build

# The vendored llhttp corpus is upstream's bytes and is never hand-edited.
# This is the only way they are written: the initial vendor and every refresh
# run the same script, so a refresh cannot drift from however the first copy
# happened to be made. The source checkout is named here, never in the tree.
corpus-refresh:   ## re-vendor the llhttp corpus (needs LLHTTP_ROOT=/path/to/llhttp)
	$(CMAKE) -DLLHTTP_ROOT="$(LLHTTP_ROOT)" -P cmake/HttparseCorpusRefresh.cmake

# src/generated/ is DERIVED: emitted from src/httparse/grammar.sls, committed so
# that what this project ships is reviewable as a diff and loadable without a
# generator. The determinism lane re-emits and compares bytes, so a grammar edit
# without a refresh reddens rather than shipping a stale artifact. This target
# and that lane run the same script.
parser-refresh: configure   ## re-emit the checked-in generated parser
	$(CMAKE) --build build/dev --target httparse_parser_refresh

# Each site target first checks CMARK_GFM_ROOT names a chez-cmark-gfm checkout,
# so a missing path fails with a sentence rather than a library-not-found.
cmark-gfm-root:   ## check that CMARK_GFM_ROOT names a chez-cmark-gfm checkout
	@test -n "$(CMARK_GFM_ROOT)" || { echo "set CMARK_GFM_ROOT=/path/to/chez-cmark-gfm" >&2; exit 2; }
	@test -f "$(CMARK_GFM_ROOT)/src/cmark/gfm.sls" || { echo "$(CMARK_GFM_ROOT) is not a chez-cmark-gfm checkout" >&2; exit 2; }

# docs/*.md plus site/index.md, rendered to build/site/ through chez-cmark-gfm.
site: cmark-gfm-root   ## render docs/ into build/site/ (needs CMARK_GFM_ROOT)
	@mkdir -p build/site
	@CHEZSCHEMELIBDIRS=$(SITE_LIBDIRS) SITE_REF="$(SITE_REF)" \
	  $(CHEZ) --program build-site.sps
	@cp site/style.css build/site/style.css
	@echo "site: build/site ready (open build/site/index.html)"

# The generator's own suites first, then the real site checked in memory: the
# nav lists exactly docs/*.md, every link and anchor resolves, no .md link
# leaks into the HTML, and preformatted code is never reflowed.
check-site: cmark-gfm-root   ## test the site generator, then check docs/ with it
	@CHEZSCHEMELIBDIRS=$(SITE_LIBDIRS) $(CHEZ) --program test/site/test-site.sps
	@CHEZSCHEMELIBDIRS=$(SITE_LIBDIRS) $(CHEZ) --program test/site/test-site-render.sps
	@CHEZSCHEMELIBDIRS=$(SITE_LIBDIRS) SITE_REF="$(SITE_REF)" \
	  $(CHEZ) --program test/site/site-check.sps

# Builds this package with `git archive`, as Akku's archive does, and checks
# that the archive leaves out .plans and AGENTS.md. Then installs it with Akku
# as a consumer would, and checks that exactly the libraries under src/
# install and that a program parses a request with only Akku's library path.
# Needs akku.
check-akku:   ## install with Akku as a consumer would, and check what lands
	@AKKU="$(AKKU)" CHEZ="$(CHEZ)" sh test/akku/check-akku.sh

# CONTRIBUTING.md and the pull-request template tell people which targets to
# run, so each `make TARGET` they quote, in backticks, must be one of these.
# A file that quotes none fails too: a misread file holds no bad target either.
# Every .PHONY target needs a '## ' note, or 'help' leaves it out.
check-help:   ## fail if a target has no description, or the contributor docs quote one that is not a target
	@missing=0; \
	targets=$$(awk '/^\.PHONY:/ { $$1=""; print }' Makefile); \
	for t in $$targets; do \
	  grep -qE "^$$t:.*## " Makefile || { echo "check-help: '$$t' has no '## ' description" >&2; missing=1; }; \
	done; \
	for f in CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md; do \
	  [ -f "$$f" ] || { echo "check-help: $$f is missing" >&2; missing=1; continue; }; \
	  quoted=$$(grep -oE '`[^`]*`' "$$f" | grep -oE '(^|[` ])make [a-z][a-z0-9-]*' | awk '{ print $$2 }' | sort -u); \
	  [ -n "$$quoted" ] || { echo "check-help: $$f quotes no make target, so this check read nothing in it" >&2; missing=1; }; \
	  for t in $$quoted; do \
	    case " $$targets " in \
	      *" $$t "*) ;; \
	      *) echo "check-help: $$f quotes 'make $$t', and $$t is not a target" >&2; missing=1 ;; \
	    esac; \
	  done; \
	done; \
	exit $$missing
