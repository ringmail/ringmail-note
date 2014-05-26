package Note::Param;
use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(get_param);

sub get_param
{
	my ($obj) = shift;
	if (ref($_[0]) && $_[0] =~ /HASH/)
	{
		return ((wantarray) ? ($obj, $_[0]) : ($_[0]));
	}
	else
	{
		return ((wantarray) ? ($obj, {@_}) : ({@_}));
	}
}

1;

