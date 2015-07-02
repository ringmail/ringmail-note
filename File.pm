package Note::File;
use strict;
use warnings;
no warnings 'uninitialized';

use Moose;

has 'file' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

sub exists
{
	my ($obj) = @_;
	my $fn = $obj->file();
	return (-e $fn);
}

1;

