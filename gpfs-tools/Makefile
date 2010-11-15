
.PHONY: test src deb clean distclean

NAME = gpfs-tools
# Makefile can't handle parens in version here... use tr to strip.
VERSION = $(shell head -n1 debian/changelog | gawk '{match($$2,/v(.*)-/,a);print a[1];}' | tr -d '()')
RELEASE = $(shell head -n1 debian/changelog | gawk '{match($$2,/v.*-(.*)/,a);print a[1];}' | tr -d '()')

MAKEFILE = Makefile

SCRIPTS = scripts/gpfscrfs.sh

PERL = lib/gpfsmapper.pm \
scripts/gpfsmapper

SOURCES = $(SCRIPTS) $(PERL)

# Override this in the environment if so desired
INSTALLDIR = /usr/sbin

.PHONY: clean dist install version

all: noop

noop:
	@echo noop

install: $(SOURCES)
	install -d $(DESTDIR)$(INSTALLDIR)
	for FILE in $(SOURCES) ; do \
		install -m 0755 $$FILE $(DESTDIR)$(INSTALLDIR) ; \
	done

tgz: $(NAME)-${VERSION}.tar.gz
$(NAME)-${VERSION}.tar.gz: $(SOURCES)
	rm -f $(NAME)-${VERSION}.tar.gz
	mkdir -p $(NAME)-${VERSION}
	cp -aup $(MAKEFILE) $(NAME)-${VERSION}/
	cp -aup $(SOURCES) $(NAME)-${VERSION}/
	tar czvf $(NAME)-${VERSION}.tar.gz $(NAME)-${VERSION}/
	rm -rf $(NAME)-${VERSION}/

deb: src
	dpkg-buildpackage ||:
	mkdir -p dist || exit 1
	@mv ../$(NAME)_0v$(VERSION)-$(RELEASE).dsc ./dist/
	@mv ../$(NAME)_0v$(VERSION)-$(RELEASE).tar.gz ./dist/
	@mv ../$(NAME)_0v$(VERSION)-$(RELEASE)_i386.changes ./dist/
	@mv ../$(NAME)_0v$(VERSION)-$(RELEASE)_all.deb ./dist/
	@find ./dist -type f

clean:
	rm -rf $(NAME)-${VERSION}/
	rm -f $(NAME)-${VERSION}.tar.gz
	rm -rf debian/$(NAME)
	rm -rf debian/$(NAME).*
	rm -rf debian/files

distclean: clean
	rm -rf dist/
