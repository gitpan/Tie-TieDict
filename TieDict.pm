#!/usr/bin/perl -Tw
#Copyright 1998-1999, Randall Maas.  All rights reserved.  This program is free
#software; you can redistribute it and/or modify it under the same terms as
#PERL itself.

package Tie::TieDict;
use vars qw($VERSION @ISA);
use AutoLoader 'AUTOLOAD';
@ISA=qw(AutoLoader);
$Version='0.0';
use Search::Dict;
use POSIX;
use strict;
1;

#Node structure [FileHandle, $FileName, Flags, Cache,TmpName]
#Flags bits
#  0 -- Ignore Case
#  1 -- Dictionary Order
#  2 -- Cache changed...
#  3 -- If the entire dictionary has been scanned

sub TIEHASH
{
   my $self=shift;
   my ($FN,$FH);
   if (ref $_[0] eq 'GLOB')
     {
	$FH = $_[0];
     }
    else
     {
        $FN=$_[0];
        my $H;
        open H, "<$FN";
        $FH=\*H;
     }

   my @A=(1,1);
   if (defined $_[1]) {$A[0]=$_[1]?1:0;}
   if (defined $_[2]) {$A[1]=$_[2]?1:0;}
   my $V=($A[0]<<1)|$A[1];
   return bless [$FH,$FN,$V,{}], $self;
}

__END__
sub FIRSTKEY
{
   my $self=shift;
   #Go to the start of the dictionary
   seek $self->[0],0,SEEK_SET;
   $self->NEXTKEY(@_);
}

sub NEXTKEY
{
   my $F=$_[0]->[0];
   while (my $L = <$F>)
   {
      chomp $L;
      if (!($L=~/^\s*([^\s]?[^;:]*[^\s-]+)\s*\-+\s*(.*)/) &&
	  !($L=~/^\s*([^\s]?[^:;]*[^\s]+)\s*(.*)$/))
      {next;}
      my $key=$1;
      my $Pos = tell $F;
      
      if (exists $_[0]->[3]->{$key})
        {
	   #Skip past all of these that have the key we already scanned.
	   while ($L =<$F> &&
		 ($L =~ /^\s*([^\s]?[^:;]*[^\s-]+)\s*\-+/ ||
		  $L =~ /^\s*([^\s]?[^:;]*[^\s]+)\s*$/) && $1 eq $key)
	    {
	       $Pos = tell $F;
	    }

	   seek $F, $Pos, SEEK_SET;
	   return $key;
        }

      push @{$_[0]->[3]->{$key}}, $_[0]->Data_scan($2);

    LINE:
      while ($L =~ <$F>)
      {
	  chomp $L;
	  if (!($L=~/^\s*([^\s]?[^:;]*[^\s-]+)\s*\-+\s*(.*)$/) || $1 ne $key)
	    {
	       seek $F, $Pos, SEEK_SET;
	       last LINE;
	    }
	  push @{$_[0]->[3]->{$key}}, $_[0]->Data_scan($2);
	  if (eof $F) {return $key;}
	  $Pos = tell $F;
      }
      return $key;
   }
   undef;
}

sub FETCH
{
   my $self=shift;
   my $key = shift;

   #Lower case the key as neccessary
   if ($self->[2] & 1) {$key=lc($key);}

   if (!$self->EXISTS($key)) {return undef;}
   return $self->[3]->{$key};
}

sub EXISTS
{
   my $self=shift;
   my $Cache=$self->[3];
   my $key=$_[0];
   
   #Lower case the key as neccessary
   if ($self->[2] & 1) {$key=lc($key);}

   return 1 if exists $Cache->{$key};
   return 0 if look($self->[0], $key,$self->[2]&2,$self->[2]&1) < 0;
   return 0 if eof $self->[0];

   my $F=$self->[0];
   #Scan all of the definitions
   LINE:
   while (my $L = <$F>)
    {
       chomp $L;
       if (!$L=~/^\s*([^\s]?[^:]*[^\s-]?)\s*\-+\s*(.*)$/ || $1 ne $key)
         {
            last LINE;
         }
       push @{$Cache->{$key}}, $self->Data_scan($2);
    }

   return exists $Cache->{$key};
}

sub Data_scan {$_[1];}
sub Data_fmt  {$_[1];}

sub STORE
{
   my $self=shift;
   my $key = shift;

   #Lower case the key as neccessary
   if ($self->[2] & 1) {$key=lc($key);}

   #Store it in our cache.
   $self->[3]->{$key} = $_[0];

   #Mark the object as changed.
   $self->[2] |= 4;
}

sub DELETE
{
   #Remove it from our cache
   delete $_[0]->[3]->{$_[1]};

   #Mark the object as changed.
   $_[0]->[2] |= 4;
}

sub Sync
{
   # Spit out the new category file
   my $self=shift;

   #See if there is no work to do.
   if (!($self->[2]&4)) {return;}

   my $Rdir='';
   if (defined $self->[1])
     {
	#Come up with a unique name
	my $TmpName = "bm$$";
	my $i=0;
	while (-e $TmpName)
	 {
	    $TmpName = "bm$$-$i";
	    $i++;
	 }
	$self->[4]=$TmpName;
	$Rdir=">$TmpName";
     }
    

   #Make the sorting parameters match our lookup parameters.
   my $Args='';
   if ($self->[2] & 1) {$Args.='-f ';}
   if ($self->[2] & 2) {$Args.='-d ';}
   open G, "|sort $Args $Rdir" or die "Couldn't open temporary file: $!\n";
    
   #Dump our data
   my $Cache=$self->[4];
   foreach my $I (keys %{$Cache})
    {
       foreach my $Ln (@{$Cache->{$I}})
	{
           print G "$I -- ", $self->Data_fmt($Ln)."\n";
        }
    }

   #Now copy everything *else* from the old dictionary...
   #Go to the start of the dictionary
   seek $self->[0],0,SEEK_SET;
   my $F=$self->[0];
   while (<$F>)
   {
      chomp;
      if (!/^\s*([^\s][^:]+[^\s-]+)\s*\-+/ && !/^\s*([^\s][^:]+[^\s]+)\s*$/)
      {next;}
      if (exists $Cache->{$1}) {next;}
      print G $_,"\n";
   }
    
   close G;
    
   # Rename it now.
   if (defined $self->[4] && -e $self->[4])
     {
	rename $self->[4], $self->[1] or
	    die "Couldn't replace book mark categories file: $!\n";
	undef $self->[4];
     }
}

sub DESTROY
{
   #Synchronize any changes with the stuff on the disk
   $_[0]->Sync;

   #Take care of any trash
   if (defined $_[0]->[4] && -e $_[0]->[4]) {unlink $_[0]->[4];}
}

=head1 NAME

C<Tie::TieDict> -- A Perl tie to a dictionary file

=head1 SYNOPSIS

  tie %MyDict, 'Tie::TieDict', *FILEHANDLE, $Dict, $fold

  tie %MyDict, 'Tie::TieDict', $FileName, $Dict, $fold

I<dict> is optional; defaults to true.  If I<dict> is true, search the file
in dictionary order  -- ignore anything but whitespace and word characters.

I<fold> is optional; defaults to true.  If I<fold> is true, ignore case.

=head1 DESCRIPTION

=head2 Methods

C<Data_scan> -- this scans the passed string and returns the working structure
for whatever the string is.  Defaults to just returning the string; override
this method if you want something better.

C<Data_fmt> -- this formats the passed structure into a string.  This structure
was (most likely) generated by C<Data_scan> and should able to be read by it
later.

=head2 Format of file

  KEY - DATA

The KEY begins with any non space character, may otherwise contain any
character, but must end with a character other than a dash or a space.
The DATA part is scanned by the C<Data_scan> method.

=head1 AUTHOR

Randall Maas (L<randym@acm.org>, L<http://www.hamline.edu/~rcmaas/>)

=cut

# =item C<--regexp=>pattern=cut

