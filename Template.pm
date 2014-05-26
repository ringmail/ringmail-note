package Note::Template;
use strict;
use warnings;

use Moose;
use Template;

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

sub apply
{
	my ($obj, $path, $data) = @_;
	my $t = new Template({
		'INCLUDE_PATH' => $obj->root(),
	});
	my $res = '';
	unless ($t->process($path, $data, \$res))
	{
		die($t->error());
	}
	return $res;
}

1;

