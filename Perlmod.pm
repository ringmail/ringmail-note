package Note::Perlmod;
use strict;
use warnings;
use vars qw(@ISA @EXPORT);

use Module::Load;
use Module::Refresh;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(perl_module);

sub perl_module
{
	my ($module) = shift;
	# read perl package for class
	load($module);

	# refresh module for development
	my $classpath = $module. '.pm';
	$classpath =~ s/::/\//g;
	Module::Refresh->refresh_module($classpath);
}

1;

