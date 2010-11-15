#
# $Id: Makefile,v 1.20 2009/10/20 15:05:41 matt Exp $
#

.PHONY: test src rpm clean distclean

NAME = jiraclient

RPMSPEC = $(NAME).spec

VERSION = $(shell awk '{ if ($$0 ~ /^Version:/) { print $$2; exit; }}' $(RPMSPEC) )
RELEASE = $(shell awk '{ if ($$0 ~ /^Release:/) { print $$2; exit; }}' $(RPMSPEC) )

TAGV = $(shell echo $(VERSION)-$(RELEASE) | sed -e 's/\./_/g' )
TAG = $(NAME)-$(TAGV)

SOURCES = src/jiraclient.py

TEST = test

CONFIG = jiraclientrc

ALLSOURCES = $(SOURCES) $(TEST) $(CONFIG) $(RPMSPEC)

all: deb

# Make build area
build:
	bash -c "mkdir -p build/{SOURCES,SPECS,BUILD,RPMS,SRPMS,buildroot}"

test:
	@VER=`awk '/version =/{print $$3}' src/jiraclient.py | tr -d '"'` ; \
	if [ "$(VERSION)" != "$${VER}" ]; then \
	  echo "Version mismatch: $(VERSION) != $${VER}" ; \
		exit; \
	fi

tgz: $(NAME)-$(VERSION).tar.gz

$(NAME)-$(VERSION).tar.gz: $(ALLSOURCES)
	mkdir -p $(NAME)-$(VERSION)
	for FILE in $(ALLSOURCES); do \
	 rsync -a --exclude .svn --exclude CVS --delete $$FILE $(NAME)-$(VERSION)/ ; \
	done
	tar -cvzf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)
	rm -rf $(NAME)-$(VERSION)

src: test build tgz
	cp -f $(RPMSPEC) ./build/SPECS/
	cp -f $(NAME)-$(VERSION).tar.gz ./build/SOURCES/

srpm: src
	mkdir -p dist
	rpmbuild --define "_topdir $(PWD)/build/" \
	--define "_tmppath $(PWD)/build/buildroot" \
	-bs --nodeps ./build/SPECS/$(RPMSPEC)
	find ./build/ -type f -name "*.rpm" -exec mv {} ./dist \;
	@echo "Build results:"
	@find ./dist -type f

rpm: src
	mkdir -p dist
	rpmbuild --define "_topdir $(PWD)/build/" \
	--define "_tmppath $(PWD)/build/buildroot" \
	-ta ./build/SOURCES/$(NAME)-$(VERSION).tar.gz
	find ./build/ -type f -name "*.rpm" -exec mv {} ./dist \;
	@echo "Build results:"
	@find ./dist -type f

deb: src
	mkdir -p dist
	dpkg-buildpackage ||:
	@mv ../jiraclient_$(VERSION)-$(RELEASE).dsc ./dist
	@mv ../jiraclient_$(VERSION)-$(RELEASE).tar.gz ./dist
	@mv ../jiraclient_$(VERSION)-$(RELEASE)_all.deb ./dist
	@mv ../jiraclient_$(VERSION)-$(RELEASE)_i386.changes ./dist
	@find ./dist -type f

clean:
	find . -type f -name "*.pyc" -exec rm {} \;
	rm -rf src/*.pyc
	rm -rf build/
	rm -f $(NAME)-$(VERSION).tar.gz
	rm -rf debian/$(NAME)
	rm -rf debian/$(NAME).*
	rm -rf debian/files

distclean: clean
	rm -rf dist/
