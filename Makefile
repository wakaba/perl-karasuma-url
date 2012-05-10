all:

# ------ Setup ------

WGET = wget
PERL = perl
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120328

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

local-perl perl-version perl-exec \
local-submodules config/perl/libs.txt \
carton-install carton-update carton-install-module \
remotedev-test remotedev-reset remotedev-reset-setupenv \
generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@

# ------ Test ------

PERL_ENV = PATH=$(PERL_PATH):$(PATH) PERL5LIB=$(shell cat config/perl/libs.txt)
PROVE = prove

test: test-deps safetest

test-deps: carton-install config/perl/libs.txt

safetest:
	$(PERL_ENV) $(PROVE) t/**.t
