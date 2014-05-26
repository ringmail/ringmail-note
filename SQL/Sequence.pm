package Note::SQL::Sequence;
use strict;
use warnings;

use vars qw();

use Moose;
use Note::Param;
use Note::SQL::Database;

has 'database' => (
	'is' => 'rw',
	'isa' => 'Note::SQL::Database',
);

has 'counter' => (
	'is' => 'rw',
	'isa' => 'Int',
	'default' => sub { return 0; },
);

sub nextid
{
	my ($obj) = @_;
	my $db = $obj->database();
	if (defined $db)
	{
		return $db->query('select nextid()')->[0]->[0];
	}
	my $ctr = $obj->counter();
	$obj->counter($ctr + 1);
	return $ctr;
}

1;
