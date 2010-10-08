#
# $Id: Makefile,v 1.20 2009/10/20 15:05:41 matt Exp $
#

.PHONY: src rpm clean distclean

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

all: rpm

# Make build area
build:
	bash -c "mkdir -p build/{SOURCES,SPECS,BUILD,RPMS,SRPMS,buildroot}"

tgz: $(NAME)-$(VERSION).tar.gz

$(NAME)-$(VERSION).tar.gz: $(ALLSOURCES)
	mkdir -p $(NAME)-$(VERSION)
	for FILE in $(ALLSOURCES); do \
	 rsync -a --exclude .svn --exclude CVS --delete $$FILE $(NAME)-$(VERSION)/ ; \
	done
	tar -cvzf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)
	rm -rf $(NAME)-$(VERSION)

src: build tgz
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

clean:
	find . -type f -name "*.pyc" -exec rm {} \;
	rm -rf src/*.pyc
	rm -rf build/
	rm -f $(NAME)-$(VERSION).tar.gz

distclean: clean
	rm -rf dist/
