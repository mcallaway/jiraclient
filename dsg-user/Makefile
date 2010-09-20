
NAME = dsg-user-scripts
VERSION = $(shell awk -F: '/^Version:/{print $$2}' $(NAME).spec | tr -d ' ' )

SPEC = dsg-user-scripts.spec

MAKEFILE = Makefile

SCRIPTS = dsg-homearchive.sh \
dsg-homedir.sh \
dsg-mailalias.sh \
dsg-mailarchive.sh \
dsg-mailimap.sh \
dsg-passwd.sh \
dsg-samba.sh \
dsg-useradd.sh \
dsg-userdel.sh \
rm-alias.sh \
rm-ssh.sh

PERL = dsg-userAD.pl \
dsg-userldap.pl

SOURCES = $(SCRIPTS) $(PERL)

# Override this in the environment if so desired
INSTALLDIR = /dsg/share/scripts

.PHONY: clean dist install version

all: dist

install: $(SOURCES)
	install -d $(DESTDIR)$(INSTALLDIR)
	for FILE in $(SOURCES) ; do \
		install -m 0755 $$FILE $(DESTDIR)$(INSTALLDIR) ; \
	done

version:
	sed -i -r "s/version=.*/version=$(VERSION)/" $(SCRIPTS)

tgz: $(NAME)-${VERSION}.tar.gz version
$(NAME)-${VERSION}.tar.gz: $(SOURCES) $(SPEC)
	rm -f $(NAME)-${VERSION}.tar.gz
	mkdir -p $(NAME)-${VERSION}
	cp -aup $(SPEC) $(NAME)-${VERSION}/
	cp -aup $(MAKEFILE) $(NAME)-${VERSION}/
	cp -aup $(SOURCES) $(NAME)-${VERSION}/
	tar czvf $(NAME)-${VERSION}.tar.gz $(NAME)-${VERSION}/
	rm -rf $(NAME)-${VERSION}/

rpm: $(NAME)-${VERSION}.noarch.rpm
$(NAME)-${VERSION}.noarch.rpm: $(NAME)-${VERSION}.tar.gz
	rpmbuild -ta $(NAME)-${VERSION}.tar.gz

dist: rpm

clean:
	rm -rf $(NAME)-${VERSION}/
	rm -f $(NAME)-${VERSION}.tar.gz
