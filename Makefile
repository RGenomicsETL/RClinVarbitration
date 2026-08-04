# Keep this release artifact name in sync with DESCRIPTION.
PKG = RClinVarbitration
VER = 0.1.1.9000
TAR = $(PKG)_$(VER).tar.gz

.PHONY: rd build install rdm errata site test check clean

rd:
	Rscript -e 'roxygen2::roxygenize(load_code = "source")'

build: rd
	R CMD build .

install: build
	R CMD INSTALL --preclean $(TAR)

rdm: rd
	Rscript -e 'rmarkdown::render("README.Rmd", output_file = "README.md", quiet = TRUE)'
	rm -f README.html

errata:
	Rscript -e 'rmarkdown::render("docs/ERRATA.Rmd", quiet = TRUE)'

site: rd errata
	Rscript -e 'pkgdown::build_site(new_process = FALSE, install = FALSE)'

test: install
	Rscript -e 'tinytest::test_package("RClinVarbitration", ncpu = 1L)'

check: build
	R CMD check --no-manual $(TAR)

clean:
	rm -rf $(PKG).Rcheck $(TAR) man
	rm -rf inst/rclinvarbitration_extension/build
