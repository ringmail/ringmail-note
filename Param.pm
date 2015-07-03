package Note::Param;
use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw(@ISA @EXPORT);

use Scalar::Util ('reftype');

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(get_param list_apply);

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

sub list_apply
{
	my ($input, $fn) = @_;
	unless (ref($fn) eq 'CODE')
	{
		die("Invalid function");
	}
	if (ref($input) && reftype($input) eq 'ARRAY')
	{
		foreach my $i (@$input)
		{
			$fn->($i);
		}
	}
	else
	{
		$fn->($input);
	}
}

1;

