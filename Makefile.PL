#!/usr/bin/perl

#My script files
opendir D, 'bin';
my ($A,$b,@_Scripts)=readdir D;
closedir D;
my @Scripts;
foreach my $I (@_Scripts)
{
  if ($I=~/,v$/i || $I eq 'makefile') {next;}
  push @Scripts, "bin/$I";
}

use ExtUtils::MakeMaker;
#see lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'    => 'Tie::TieDict',
    'dist'    => {COMPRESS=> 'gzip -9f', SUFFIX=>'gz', 
                  POSTOP => 'mv $(DISTNAME)-$(VERSION).tar.gz ../',
		  TARFLAGS=>'cvfF'
                  },
    'linkext' => {LINKTYPE => '' }, 
    'clean'   => {FILES => "*% *.html *~ www-* .htp* .htg*"},
    VERSION => '0.2',
    'EXE_FILES' => [@Scripts],
    'MAN1PODS'  => {map {my $a=$_; s#^bin/#./blib/man1/#; $a,"$_.\$(MAN1EXT)";} @Scripts},
);
