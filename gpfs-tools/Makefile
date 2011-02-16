
.PHONY: test tgz deb rpm clean distclean

NAME = gpfs-tools
# Makefile can't handle parens in version here... use tr to strip.
VERSION = $(shell head -n1 debian/changelog | gawk '{match($$2,/(.*)-/,a);print a[1];}' | tr -d '()')
RELEASE = $(shell head -n1 debian/changelog | gawk '{match($$2,/.*-(.*)/,a);print a[1];}' | tr -d '()')

MAKEFILE = Makefile

SPEC = rpm/$(NAME).spec

SOURCES = scripts/ debian/ rpm/

SCRIPTS = scripts/gpfscrfs.sh \
scripts/gpfsmapper.pl

# Override this in the environment if so desired
INSTALLDIR = /usr/sbin

.PHONY: clean dist install version

all: noop

noop:
	@echo noop

test:
	prove -I scripts/ t/gpfsmapper.t

install: $(SCRIPTS)
	install -d $(DESTDIR)$(INSTALLDIR)
	for FILE in $(SCRIPTS) ; do \
		install -m 0755 $$FILE $(DESTDIR)$(INSTALLDIR) ; \
	done

tgz: $(NAME)-$(VERSION).tar.gz
$(NAME)-$(VERSION).tar.gz: $(SOURCES)
	rm -f $(NAME)-$(VERSION).tar.gz
	mkdir -p $(NAME)-$(VERSION)
	cp -aup $(MAKEFILE) $(NAME)-$(VERSION)/
	cp -aup $(SOURCES) $(NAME)-$(VERSION)/
	tar czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)/
	rm -rf $(NAME)-$(VERSION)/

deb:
	dpkg-buildpackage ||:
	mkdir -p dist || exit 1
	@mv ../$(NAME)_$(VERSION)-$(RELEASE).dsc ./dist/
	@mv ../$(NAME)_$(VERSION)-$(RELEASE).tar.gz ./dist/
	@mv ../$(NAME)_$(VERSION)-$(RELEASE)_i386.changes ./dist/
	@mv ../$(NAME)_$(VERSION)-$(RELEASE)_all.deb ./dist/
	@mv $(NAME)-$(VERSION).tar.gz dist/
	@find ./dist -type f

RELEASE = $(shell awk '/Release:/ {print $$2}' $(SPEC) )
rpm: tgz
	mkdir -p build dist
	rpmbuild --define '_topdir $(PWD)/build' \
	  -ta $(NAME)-$(VERSION).tar.gz
	@mv ./build/SRPMS/$(NAME)-$(VERSION)-$(RELEASE).src.rpm dist/
	@mv ./build/RPMS/noarch/$(NAME)-$(VERSION)-$(RELEASE).noarch.rpm dist/
	@mv $(NAME)-$(VERSION).tar.gz dist/
	@rm -rf build

clean:
	rm -rf $(NAME)-${VERSION}/
	rm -f $(NAME)-${VERSION}.tar.gz
	rm -rf debian/$(NAME)
	rm -rf debian/$(NAME).*
	rm -rf debian/files

distclean: clean
	rm -rf dist/
