
NAME := batch-fasta
DESTDIR :=
PREFIX :=/usr
SBINDIR :=/sbin

all:

install:
	install -D -m 0755 scripts/batch_fasta.pl $(DESTDIR)$(PREFIX)$(SBINDIR)/batch_fasta

deb:
	debuild --no-tgz-check || exit 1
	mkdir -p dist
	mv ../$(NAME)-* dist

realclean:
	rm -f debian/batch-fasta-perl.debhelper.log
	rm -f debian/batch-fasta-perl.substvars
	rm -f debian/files
	rm -rf debian/batch-fasta-perl/
	rm -rf dist
